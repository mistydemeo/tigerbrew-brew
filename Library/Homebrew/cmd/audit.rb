require 'formula'
require 'utils'
require 'superenv'

module Homebrew extend self
  def audit
    formula_count = 0
    problem_count = 0

    ff = if ARGV.named.empty?
      Formula
    else
      ARGV.formulae
    end

    ff.each do |f|
      fa = FormulaAuditor.new f
      fa.audit

      unless fa.problems.empty?
        puts "#{f.name}:"
        fa.problems.each { |p| puts " * #{p}" }
        puts
        formula_count += 1
        problem_count += fa.problems.size
      end
    end

    unless problem_count.zero?
      ofail "#{problem_count} problems in #{formula_count} formulae"
    end
  end
end

class Module
  def redefine_const(name, value)
    __send__(:remove_const, name) if const_defined?(name)
    const_set(name, value)
  end
end

# Formula extensions for auditing
class Formula
  def head_only?
    @head and @stable.nil?
  end

  def text
    @text ||= FormulaText.new(@path)
  end
end

class FormulaText
  def initialize path
    @text = path.open('r') { |f| f.read }
  end

  def without_patch
    @text.split("__END__")[0].strip()
  end

  def has_DATA?
    /\bDATA\b/ =~ @text
  end

  def has_END?
    /^__END__$/ =~ @text
  end

  def has_trailing_newline?
    /\Z\n/ =~ @text
  end
end

class FormulaAuditor
  attr_reader :f, :text, :problems

  BUILD_TIME_DEPS = %W[
    autoconf
    automake
    boost-build
    bsdmake
    cmake
    imake
    intltool
    libtool
    pkg-config
    scons
    smake
    swig
  ]

  def initialize f
    @f = f
    @problems = []
    @text = f.text.without_patch
    @specs = %w{stable devel head}.map { |s| f.send(s) }.compact

    # We need to do this in case the formula defines a patch that uses DATA.
    f.class.redefine_const :DATA, ""
  end

  def audit_file
    unless f.path.stat.mode.to_s(8) == "100644"
      problem "Incorrect file permissions: chmod 644 #{f.path}"
    end

    if f.text.has_DATA? and not f.text.has_END?
      problem "'DATA' was found, but no '__END__'"
    end

    if f.text.has_END? and not f.text.has_DATA?
      problem "'__END__' was found, but 'DATA' is not used"
    end

    unless f.text.has_trailing_newline?
      problem "File should end with a newline"
    end
  end

  def audit_deps
    # Don't depend_on aliases; use full name
    aliases = Formula.aliases
    f.deps.select { |d| aliases.include? d.name }.each do |d|
      problem "Dependency #{d} is an alias; use the canonical name."
    end

    # Check for things we don't like to depend on.
    # We allow non-Homebrew installs whenever possible.
    f.deps.each do |dep|
      begin
        dep_f = dep.to_formula
      rescue FormulaUnavailableError
        problem "Can't find dependency #{dep.name.inspect}."
      end

      dep.options.reject do |opt|
        dep_f.build.has_option?(opt.name)
      end.each do |opt|
        problem "Dependency #{dep} does not define option #{opt.name.inspect}"
      end

      case dep.name
      when *BUILD_TIME_DEPS
        # Build deps should be tagged
        problem <<-EOS.undent unless dep.tags.any? || f.name =~ /automake/ && dep.name == 'autoconf'
        #{dep} dependency should be "depends_on '#{dep}' => :build"
        EOS
      when "git", "python", "ruby", "emacs", "mysql", "mercurial"
        problem <<-EOS.undent
          Don't use #{dep} as a dependency. We allow non-Homebrew
          #{dep} installations.
          EOS
      when "postgresql"
        # Postgis specifically requires a Homebrewed postgresql
        unless f.name == "postgis"
          problem <<-EOS.undent
            Don't use #{dep} as a dependency. We allow non-Homebrew
            #{dep} installations.
          EOS
        end
      when 'gfortran'
        problem "Use ENV.fortran during install instead of depends_on 'gfortran'"
      when 'open-mpi', 'mpich2'
        problem <<-EOS.undent
          There are multiple conflicting ways to install MPI. Use an MPIDependency:
            depends_on MPIDependency.new(<lang list>)
          Where <lang list> is a comma delimited list that can include:
            :cc, :cxx, :f90, :f77
          EOS
      end
    end
  end

  def audit_conflicts
    f.conflicts.each do |req|
      begin
        Formula.factory req.formula
      rescue FormulaUnavailableError
        problem "Can't find conflicting formula \"#{req.formula}\"."
      end
    end
  end

  def audit_urls
    unless f.homepage =~ %r[^https?://]
      problem "The homepage should start with http or https (url is #{f.homepage})."
    end

    # Check for http:// GitHub homepage urls, https:// is preferred.
    # Note: only check homepages that are repo pages, not *.github.com hosts
    if f.homepage =~ %r[^http://github\.com/]
      problem "Use https:// URLs for homepages on GitHub (url is #{f.homepage})."
    end

    # Google Code homepages should end in a slash
    if f.homepage =~ %r[^https?://code\.google\.com/p/[^/]+[^/]$]
      problem "Google Code homepage should end with a slash (url is #{f.homepage})."
    end

    if f.homepage =~ %r[^http://.*\.github\.com/]
      problem "GitHub pages should use the github.io domain (url is #{f.homepage})"
    end

    urls = @specs.map(&:url)

    # Check GNU urls; doesn't apply to mirrors
    urls.grep(%r[^(?:https?|ftp)://(?!alpha).+/gnu/]).each do |u|
      problem "\"ftpmirror.gnu.org\" is preferred for GNU software (url is #{u})."
    end

    # the rest of the checks apply to mirrors as well
    urls.concat(@specs.map(&:mirrors).flatten)

    # Check SourceForge urls
    urls.each do |p|
      # Is it a filedownload (instead of svnroot)
      next if p =~ %r[/svnroot/]
      next if p =~ %r[svn\.sourceforge]

      # Is it a sourceforge http(s) URL?
      next unless p =~ %r[^https?://.*\bsourceforge\.]

      if p =~ /(\?|&)use_mirror=/
        problem "Don't use #{$1}use_mirror in SourceForge urls (url is #{p})."
      end

      if p =~ /\/download$/
        problem "Don't use /download in SourceForge urls (url is #{p})."
      end

      if p =~ %r[^http://prdownloads\.]
        problem "Don't use prdownloads in SourceForge urls (url is #{p}).\n" + 
                "\tSee: http://librelist.com/browser/homebrew/2011/1/12/prdownloads-is-bad/"
      end

      if p =~ %r[^http://\w+\.dl\.]
        problem "Don't use specific dl mirrors in SourceForge urls (url is #{p})."
      end
    end

    # Check for git:// GitHub repo urls, https:// is preferred.
    urls.grep(%r[^git://[^/]*github\.com/]).each do |u|
      problem "Use https:// URLs for accessing GitHub repositories (url is #{u})."
    end

    # Check for http:// GitHub repo urls, https:// is preferred.
    urls.grep(%r[^http://github\.com/.*\.git$]).each do |u|
      problem "Use https:// URLs for accessing GitHub repositories (url is #{u})."
    end 

    # Use new-style archive downloads
    urls.select { |u| u =~ %r[https://.*/(?:tar|zip)ball/] and not u =~ %r[\.git$] }.each do |u|
      problem "Use /archive/ URLs for GitHub tarballs (url is #{u})."
    end

    if urls.any? { |u| u =~ /\.xz/ } && !f.deps.any? { |d| d.name == "xz" }
      problem "Missing a build-time dependency on 'xz'"
    end
  end

  def audit_specs
    problem "Head-only (no stable download)" if f.head_only?

    [:stable, :devel].each do |spec|
      s = f.send(spec)
      next if s.nil?

      if s.version.to_s.empty?
        problem "Invalid or missing #{spec} version"
      else
        version_text = s.version unless s.version.detected_from_url?
        version_url = Version.parse(s.url)
        if version_url.to_s == version_text.to_s
          problem "#{spec} version #{version_text} is redundant with version scanned from URL"
        end
      end

      cksum = s.checksum
      next if cksum.nil?

      len = case cksum.hash_type
        when :sha1 then 40
        when :sha256 then 64
        end

      if cksum.empty?
        problem "#{cksum.hash_type} is empty"
      else
        problem "#{cksum.hash_type} should be #{len} characters" unless cksum.hexdigest.length == len
        problem "#{cksum.hash_type} contains invalid characters" unless cksum.hexdigest =~ /^[a-fA-F0-9]+$/
        problem "#{cksum.hash_type} should be lowercase" unless cksum.hexdigest == cksum.hexdigest.downcase
      end
    end
  end

  def audit_patches
    # Some formulae use ENV in patches, so set up an environment
    ENV.with_build_environment do
      Patches.new(f.patches).select { |p| p.external? }.each do |p|
        case p.url
        when %r[raw\.github\.com], %r[gist\.github\.com/raw]
          unless p.url =~ /[a-fA-F0-9]{40}/
            problem "GitHub/Gist patches should specify a revision:\n#{p.url}"
          end
        when %r[macports/trunk]
          problem "MacPorts patches should specify a revision instead of trunk:\n#{p.url}"
        end
      end
    end
  end

  def audit_text
    if text =~ /<(Formula|AmazonWebServicesFormula|ScriptFileFormula|GithubGistFormula)/
      problem "Use a space in class inheritance: class Foo < #{$1}"
    end

    # Commented-out cmake support from default template
    if (text =~ /# system "cmake/)
      problem "Commented cmake call found"
    end

    # FileUtils is included in Formula
    if text =~ /FileUtils\.(\w+)/
      problem "Don't need 'FileUtils.' before #{$1}."
    end

    # Check for long inreplace block vars
    if text =~ /inreplace .* do \|(.{2,})\|/
      problem "\"inreplace <filenames> do |s|\" is preferred over \"|#{$1}|\"."
    end

    # Check for string interpolation of single values.
    if text =~ /(system|inreplace|gsub!|change_make_var!) .* ['"]#\{(\w+(\.\w+)?)\}['"]/
      problem "Don't need to interpolate \"#{$2}\" with #{$1}"
    end

    # Check for string concatenation; prefer interpolation
    if text =~ /(#\{\w+\s*\+\s*['"][^}]+\})/
      problem "Try not to concatenate paths in string interpolation:\n   #{$1}"
    end

    # Prefer formula path shortcuts in Pathname+
    if text =~ %r{\(\s*(prefix\s*\+\s*(['"])(bin|include|libexec|lib|sbin|share)[/'"])}
      problem "\"(#{$1}...#{$2})\" should be \"(#{$3}+...)\""
    end

    if text =~ %r[((man)\s*\+\s*(['"])(man[1-8])(['"]))]
      problem "\"#{$1}\" should be \"#{$4}\""
    end

    # Prefer formula path shortcuts in strings
    if text =~ %r[(\#\{prefix\}/(bin|include|libexec|lib|sbin|share))]
      problem "\"#{$1}\" should be \"\#{#{$2}}\""
    end

    if text =~ %r[((\#\{prefix\}/share/man/|\#\{man\}/)(man[1-8]))]
      problem "\"#{$1}\" should be \"\#{#{$3}}\""
    end

    if text =~ %r[((\#\{share\}/(man)))[/'"]]
      problem "\"#{$1}\" should be \"\#{#{$3}}\""
    end

    if text =~ %r[(\#\{prefix\}/share/(info|man))]
      problem "\"#{$1}\" should be \"\#{#{$2}}\""
    end

    # Commented-out depends_on
    if text =~ /#\s*depends_on\s+(.+)\s*$/
      problem "Commented-out dep #{$1}"
    end

    # No trailing whitespace, please
    if text =~ /[\t ]+$/
      problem "Trailing whitespace was found"
    end

    if text =~ /if\s+ARGV\.include\?\s+'--(HEAD|devel)'/
      problem "Use \"if ARGV.build_#{$1.downcase}?\" instead"
    end

    if text =~ /make && make/
      problem "Use separate make calls"
    end

    if text =~ /^[ ]*\t/
      problem "Use spaces instead of tabs for indentation"
    end

    # xcodebuild should specify SYMROOT
    if text =~ /system\s+['"]xcodebuild/ and not text =~ /SYMROOT=/
      problem "xcodebuild should be passed an explicit \"SYMROOT\""
    end

    if text =~ /ENV\.x11/
      problem "Use \"depends_on :x11\" instead of \"ENV.x11\""
    end

    # Avoid hard-coding compilers
    if text =~ %r{(system|ENV\[.+\]\s?=)\s?['"](/usr/bin/)?(gcc|llvm-gcc|clang)['" ]}
      problem "Use \"\#{ENV.cc}\" instead of hard-coding \"#{$3}\""
    end

    if text =~ %r{(system|ENV\[.+\]\s?=)\s?['"](/usr/bin/)?((g|llvm-g|clang)\+\+)['" ]}
      problem "Use \"\#{ENV.cxx}\" instead of hard-coding \"#{$3}\""
    end

    if text =~ /system\s+['"](env|export)/
      problem "Use ENV instead of invoking '#{$1}' to modify the environment"
    end

    if text =~ /version == ['"]HEAD['"]/
      problem "Use 'build.head?' instead of inspecting 'version'"
    end

    if text =~ /build\.include\?\s+['"]\-\-(.*)['"]/
      problem "Reference '#{$1}' without dashes"
    end

    if text =~ /ARGV\.(?!(debug\?|verbose\?|find[\(\s]))/
      problem "Use build instead of ARGV to check options"
    end

    if text =~ /def options/
      problem "Use new-style option definitions"
    end

    if text =~ /MACOS_VERSION/
      problem "Use MacOS.version instead of MACOS_VERSION"
    end

    cats = %w{leopard snow_leopard lion mountain_lion}.join("|")
    if text =~ /MacOS\.(?:#{cats})\?/
      problem "\"#{$&}\" is deprecated, use a comparison to MacOS.version instead"
    end

    if text =~ /skip_clean\s+:all/
      problem "`skip_clean :all` is deprecated; brew no longer strips symbols"
    end

    if text =~ /depends_on [A-Z][\w:]+\.new$/
      problem "`depends_on` can take requirement classes instead of instances"
    end
  end

  def audit
    audit_file
    audit_specs
    audit_urls
    audit_deps
    audit_conflicts
    audit_patches
    audit_text
  end

  private

  def problem p
    @problems << p
  end
end
