require 'download_strategy'
require 'dependency_collector'
require 'formula_support'
require 'formula_lock'
require 'formula_pin'
require 'hardware'
require 'bottles'
require 'patches'
require 'compilers'
require 'build_environment'
require 'build_options'


class Formula
  include FileUtils
  extend BuildEnvironmentDSL

  attr_reader :name, :path, :homepage, :downloader
  attr_reader :stable, :bottle, :devel, :head, :active_spec

  # The current working directory during builds and tests.
  # Will only be non-nil inside #stage and #test.
  attr_reader :buildpath, :testpath

  # Homebrew determines the name
  def initialize name='__UNKNOWN__', path=nil
    @name = name
    # If we got an explicit path, use that, else determine from the name
    @path = path.nil? ? self.class.path(name) : Pathname.new(path)
    @homepage = self.class.homepage

    set_spec :stable
    set_spec :devel
    set_spec :head
    set_spec :bottle do |bottle|
      # Ensure the bottle URL is set. If it does not have a checksum,
      # then a bottle is not available for the current platform.
      # TODO: push this down into Bottle; we can pass the formula instance
      # into a validation method on the bottle instance.
      unless bottle.checksum.nil? || bottle.checksum.empty?
        @bottle = bottle
        bottle.url ||= bottle_url(self)
        if bottle.cat_without_underscores
          bottle.url.gsub!(MacOS.cat.to_s,
                           MacOS.cat_without_underscores.to_s)
        end
      end
    end

    @active_spec = determine_active_spec
    validate_attributes :url, :name, :version
    @downloader = download_strategy.new(name, @active_spec)

    # Combine DSL `option` and `def options`
    options.each do |opt, desc|
      # make sure to strip "--" from the start of options
      self.class.build.add opt[/--(.+)$/, 1], desc
    end

    @pin = FormulaPin.new(self)
  end

  def set_spec(name)
    spec = self.class.send(name)
    return if spec.nil?
    if block_given? && yield(spec) || !spec.url.nil?
      instance_variable_set("@#{name}", spec)
    end
  end

  def determine_active_spec
    case
    when @head && ARGV.build_head?        then @head    # --HEAD
    when @devel && ARGV.build_devel?      then @devel   # --devel
    when @bottle && install_bottle?(self) then @bottle  # bottle available
    when @stable                          then @stable
    when @devel && @stable.nil?           then @devel   # devel-only
    when @head && @stable.nil?            then @head    # head-only
    else
      raise FormulaSpecificationError, "formulae require at least a URL"
    end
  end

  def validate_attributes(*attrs)
    attrs.each do |attr|
      if (value = send(attr).to_s).empty? || value =~ /\s/
        raise FormulaValidationError.new(attr, value)
      end
    end
  end

  def url;      active_spec.url;     end
  def version;  active_spec.version; end
  def mirrors;  active_spec.mirrors; end

  # if the dir is there, but it's empty we consider it not installed
  def installed?
    (dir = installed_prefix).directory? && dir.children.length > 0
  end

  def pinnable?
    @pin.pinnable?
  end

  def pinned?
    @pin.pinned?
  end

  def pin
    @pin.pin
  end

  def unpin
    @pin.unpin
  end

  def linked_keg
    Pathname.new("#{HOMEBREW_LIBRARY}/LinkedKegs/#{name}")
  end

  def installed_prefix
    devel_prefix = unless devel.nil?
      Pathname.new("#{HOMEBREW_CELLAR}/#{name}/#{devel.version}")
    end

    head_prefix = unless head.nil?
      Pathname.new("#{HOMEBREW_CELLAR}/#{name}/#{head.version}")
    end

    if active_spec == head || head and head_prefix.directory?
      head_prefix
    elsif active_spec == devel || devel and devel_prefix.directory?
      devel_prefix
    else
      prefix
    end
  end

  def installed_version
    require 'keg'
    Keg.new(installed_prefix).version
  end

  def prefix
    Pathname.new("#{HOMEBREW_CELLAR}/#{name}/#{version}")
  end
  def rack; prefix.parent end

  def bin;     prefix+'bin'     end
  def doc;     share+'doc'+name end
  def include; prefix+'include' end
  def info;    share+'info'     end
  def lib;     prefix+'lib'     end
  def libexec; prefix+'libexec' end
  def man;     share+'man'      end
  def man1;    man+'man1'       end
  def man2;    man+'man2'       end
  def man3;    man+'man3'       end
  def man4;    man+'man4'       end
  def man5;    man+'man5'       end
  def man6;    man+'man6'       end
  def man7;    man+'man7'       end
  def man8;    man+'man8'       end
  def sbin;    prefix+'sbin'    end
  def share;   prefix+'share'   end

  def frameworks; prefix+'Frameworks' end
  def kext_prefix; prefix+'Library/Extensions' end

  # configuration needs to be preserved past upgrades
  def etc; HOMEBREW_PREFIX+'etc' end
  # generally we don't want var stuff inside the keg
  def var; HOMEBREW_PREFIX+'var' end

  def bash_completion; prefix+'etc/bash_completion.d' end
  def zsh_completion;  share+'zsh/site-functions'     end

  # override this to provide a plist
  def plist; nil; end
  alias :startup_plist :plist
  # plist name, i.e. the name of the launchd service
  def plist_name; 'tigerbrew.mistydemeo.'+name end
  def plist_path; prefix+(plist_name+'.plist') end
  def plist_manual; self.class.plist_manual end
  def plist_startup; self.class.plist_startup end

  # Defined and active build-time options.
  def build; self.class.build; end

  def opt_prefix
    Pathname.new("#{HOMEBREW_PREFIX}/opt/#{name}")
  end

  def download_strategy
    active_spec.download_strategy
  end

  def cached_download
    downloader.cached_location
  end

  # Can be overridden to selectively disable bottles from formulae.
  # Defaults to true so overridden version does not have to check if bottles
  # are supported.
  def pour_bottle?; true end

  # Can be overridden to run commands on both source and bottle installation.
  def post_install; end

  # tell the user about any caveats regarding this package, return a string
  def caveats; nil end

  # any e.g. configure options for this package
  def options; [] end

  # patches are automatically applied after extracting the tarball
  # return an array of strings, or if you need a patch level other than -p1
  # return a Hash eg.
  #   {
  #     :p0 => ['http://foo.com/patch1', 'http://foo.com/patch2'],
  #     :p1 =>  'http://bar.com/patch2'
  #   }
  # The final option is to return DATA, then put a diff after __END__. You
  # can still return a Hash with DATA as the value for a patch level key.
  def patches; end

  # rarely, you don't want your library symlinked into the main prefix
  # see gettext.rb for an example
  def keg_only?
    kor = self.class.keg_only_reason
    not kor.nil? and kor.valid?
  end

  def keg_only_reason
    self.class.keg_only_reason
  end

  def fails_with? cc
    cc = Compiler.new(cc) unless cc.is_a? Compiler
    (self.class.cc_failures || []).any? do |failure|
      failure.compiler == cc.name && failure.build >= cc.build
    end
  end

  # sometimes the clean process breaks things
  # skip cleaning paths in a formula with a class method like this:
  #   skip_clean [bin+"foo", lib+"bar"]
  # redefining skip_clean? now deprecated
  def skip_clean? path
    return true if self.class.skip_clean_all?
    return true if path.extname == '.la' and self.class.skip_clean_paths.include? :la
    to_check = path.relative_path_from(prefix).to_s
    self.class.skip_clean_paths.include? to_check
  end

  # yields self with current working directory set to the uncompressed tarball
  def brew
    validate_attributes :name, :version

    stage do
      begin
        patch
        # we allow formulae to do anything they want to the Ruby process
        # so load any deps before this point! And exit asap afterwards
        yield self
      rescue RuntimeError, SystemCallError
        %w(config.log CMakeCache.txt).each do |fn|
          (HOMEBREW_LOGS/name).install(fn) if File.file?(fn)
        end
        raise
      end
    end
  end

  def lock
    @lock = FormulaLock.new(name)
    @lock.lock
  end

  def unlock
    @lock.unlock unless @lock.nil?
  end

  def == b
    name == b.name
  end
  def eql? b
    self == b and self.class.equal? b.class
  end
  def hash
    name.hash
  end
  def <=> b
    name <=> b.name
  end
  def to_s
    name
  end
  def inspect
    name
  end

  # Standard parameters for CMake builds.
  # Using Build Type "None" tells cmake to use our CFLAGS,etc. settings.
  # Setting it to Release would ignore our flags.
  # Setting CMAKE_FIND_FRAMEWORK to "LAST" tells CMake to search for our
  # libraries before trying to utilize Frameworks, many of which will be from
  # 3rd party installs.
  # Note: there isn't a std_autotools variant because autotools is a lot
  # less consistent and the standard parameters are more memorable.
  def std_cmake_args
    %W[
      -DCMAKE_INSTALL_PREFIX=#{prefix}
      -DCMAKE_BUILD_TYPE=None
      -DCMAKE_FIND_FRAMEWORK=LAST
      -Wno-dev
    ]
  end

  def self.class_s name
    # remove invalid characters and then camelcase it
    name.capitalize.gsub(/[-_.\s]([a-zA-Z0-9])/) { $1.upcase } \
                   .gsub('+', 'x')
  end

  # an array of all Formula names
  def self.names
    Dir["#{HOMEBREW_REPOSITORY}/Library/Formula/*.rb"].map{ |f| File.basename f, '.rb' }.sort
  end

  def self.each
    names.each do |name|
      begin
        yield Formula.factory(name)
      rescue
        # Don't let one broken formula break commands. But do complain.
        onoe "Failed to import: #{name}"
        next
      end
    end
  end
  class << self
    include Enumerable
  end

  def self.installed
    HOMEBREW_CELLAR.children.map{ |rack| factory(rack.basename) rescue nil }.compact
  end

  def self.aliases
    Dir["#{HOMEBREW_REPOSITORY}/Library/Aliases/*"].map{ |f| File.basename f }.sort
  end

  def self.canonical_name name
    name = name.to_s if name.kind_of? Pathname

    formula_with_that_name = Pathname.new("#{HOMEBREW_REPOSITORY}/Library/Formula/#{name}.rb")
    possible_alias = Pathname.new("#{HOMEBREW_REPOSITORY}/Library/Aliases/#{name}")
    possible_cached_formula = Pathname.new("#{HOMEBREW_CACHE_FORMULA}/#{name}.rb")

    if name.include? "/"
      if name =~ %r{(.+)/(.+)/(.+)}
        tap_name = "#$1-#$2".downcase
        tapd = Pathname.new("#{HOMEBREW_REPOSITORY}/Library/Taps/#{tap_name}")
        tapd.find_formula do |relative_pathname|
          return "#{tapd}/#{relative_pathname}" if relative_pathname.stem.to_s == $3
        end if tapd.directory?
      end
      # Otherwise don't resolve paths or URLs
      name
    elsif formula_with_that_name.file? and formula_with_that_name.readable?
      name
    elsif possible_alias.file?
      possible_alias.realpath.basename('.rb').to_s
    elsif possible_cached_formula.file?
      possible_cached_formula.to_s
    else
      name
    end
  end

  def self.factory name
    # If an instance of Formula is passed, just return it
    return name if name.kind_of? Formula

    # Otherwise, convert to String in case a Pathname comes in
    name = name.to_s

    # If a URL is passed, download to the cache and install
    if name =~ %r[(https?|ftp)://]
      url = name
      name = Pathname.new(name).basename
      path = HOMEBREW_CACHE_FORMULA+name
      name = name.basename(".rb").to_s

      unless Object.const_defined? self.class_s(name)
        HOMEBREW_CACHE_FORMULA.mkpath
        FileUtils.rm path, :force => true
        curl url, '-o', path
      end

      install_type = :from_url
    elsif name.match bottle_regex
      bottle_filename = Pathname(name).realpath
      version = Version.parse(bottle_filename).to_s
      name = bottle_filename.basename.to_s.rpartition("-#{version}").first
      path = Formula.path(name)
      install_type = :from_local_bottle
    else
      name = Formula.canonical_name(name)

      if name =~ %r{^(\w+)/(\w+)/([^/])+$}
        # name appears to be a tapped formula, so we don't munge it
        # in order to provide a useful error message when require fails.
        path = Pathname.new(name)
      elsif name.include? "/"
        # If name was a path or mapped to a cached formula

        # require allows filenames to drop the .rb extension, but everything else
        # in our codebase will require an exact and fullpath.
        name = "#{name}.rb" unless name =~ /\.rb$/

        path = Pathname.new(name)
        name = path.stem
        install_type = :from_path
      else
        # For names, map to the path and then require
        path = Formula.path(name)
        install_type = :from_name
      end
    end

    klass_name = self.class_s(name)
    unless Object.const_defined? klass_name
      puts "#{$0}: loading #{path}" if ARGV.debug?
      require path
    end

    begin
      klass = Object.const_get klass_name
    rescue NameError
      # TODO really this text should be encoded into the exception
      # and only shown if the UI deems it correct to show it
      onoe "class \"#{klass_name}\" expected but not found in #{name}.rb"
      puts "Double-check the name of the class in that formula."
      raise LoadError
    end

    if install_type == :from_local_bottle
      formula = klass.new(name)
      formula.downloader.local_bottle_path = bottle_filename
      return formula
    end

    raise NameError if !klass.ancestors.include? Formula
    raise NameError if klass == Formula

    return klass.new(name) if install_type == :from_name
    return klass.new(name, path.to_s)
  rescue NoMethodError
    # This is a programming error in an existing formula, and should not
    # have a "no such formula" message.
    raise
  rescue LoadError, NameError
    # Catch NameError so that things that are invalid symbols still get
    # a useful error message.
    raise FormulaUnavailableError.new(name)
  end

  def tap
    if path.realpath.to_s =~ %r{#{HOMEBREW_REPOSITORY}/Library/Taps/(\w+)-(\w+)}
      "#$1/#$2"
    else
      # remotely installed formula are not mistydemeo/master but this will do for now
      "mistydemeo/master"
    end
  end

  def self.path name
    Pathname.new("#{HOMEBREW_REPOSITORY}/Library/Formula/#{name.downcase}.rb")
  end

  def deps;         self.class.dependencies.deps;         end
  def requirements; self.class.dependencies.requirements; end

  def env
    @env ||= self.class.env
  end

  def conflicts
    requirements.grep(ConflictRequirement)
  end

  # Returns a list of Dependency objects in an installable order, which
  # means if a depends on b then b will be ordered before a in this list
  def recursive_dependencies(&block)
    Dependency.expand(self, &block)
  end

  # The full set of Requirements for this formula's dependency tree.
  def recursive_requirements(&block)
    Requirement.expand(self, &block)
  end

  def to_hash
    hsh = {
      "name" => name,
      "homepage" => homepage,
      "versions" => {
        "stable" => (stable.version.to_s if stable),
        "bottle" => bottle ? true : false,
        "devel" => (devel.version.to_s if devel),
        "head" => (head.version.to_s if head)
      },
      "installed" => [],
      "linked_keg" => (linked_keg.realpath.basename.to_s if linked_keg.exist?),
      "keg_only" => keg_only?,
      "dependencies" => deps.map {|dep| dep.to_s},
      "conflicts_with" => conflicts.map {|c| c.formula},
      "options" => [],
      "caveats" => caveats
    }

    build.each do |opt|
      hsh["options"] << {
        "option" => "--"+opt.name,
        "description" => opt.description
      }
    end

    if rack.directory?
      rack.subdirs.each do |keg|
        tab = Tab.for_keg keg

        hsh["installed"] << {
          "version" => keg.basename.to_s,
          "used_options" => tab.used_options.map(&:flag),
          "built_as_bottle" => tab.built_bottle,
          "poured_from_bottle" => tab.poured_from_bottle
        }
      end
    end

    hsh

  end

  protected

  # Pretty titles the command and buffers stdout/stderr
  # Throws if there's an error
  def system cmd, *args
    # remove "boring" arguments so that the important ones are more likely to
    # be shown considering that we trim long ohai lines to the terminal width
    pretty_args = args.dup
    if cmd == "./configure" and not ARGV.verbose?
      pretty_args.delete "--disable-dependency-tracking"
      pretty_args.delete "--disable-debug"
    end
    ohai "#{cmd} #{pretty_args*' '}".strip

    removed_ENV_variables = case if args.empty? then cmd.split(' ').first else cmd end
    when "xcodebuild"
      ENV.remove_cc_etc
    end

    if ARGV.verbose?
      safe_system cmd, *args
    else
      @exec_count ||= 0
      @exec_count += 1
      logd = HOMEBREW_LOGS/name
      logfn = "#{logd}/%02d.%s" % [@exec_count, File.basename(cmd).split(' ').first]
      mkdir_p(logd)

      rd, wr = IO.pipe
      fork do
        rd.close
        $stdout.reopen wr
        $stderr.reopen wr
        args.collect!{|arg| arg.to_s}
        exec(cmd, *args) rescue nil
        puts "Failed to execute: #{cmd}"
        exit! 1 # never gets here unless exec threw or failed
      end
      wr.close

      f = File.open(logfn, 'w')
      f.write(rd.read) until rd.eof?

      Process.wait

      unless $?.success?
        unless ARGV.verbose?
          f.flush
          Kernel.system "/usr/bin/tail", "-n", "5", logfn
        end
        f.puts
        require 'cmd/--config'
        Homebrew.write_build_config(f)
        raise ErrorDuringExecution
      end
    end
  rescue ErrorDuringExecution
    raise BuildError.new(self, cmd, args, $?)
  ensure
    f.close if f and not f.closed?
    removed_ENV_variables.each do |key, value|
      ENV[key] = value
    end if removed_ENV_variables
  end

  public

  # For brew-fetch and others.
  def fetch
    # Ensure the cache exists
    HOMEBREW_CACHE.mkpath
    downloader.fetch
    cached_download
  end

  # For FormulaInstaller.
  def verify_download_integrity fn
    active_spec.verify_download_integrity(fn)
  end

  def test
    ret = nil
    mktemp do
      @testpath = Pathname.pwd
      ret = instance_eval(&self.class.test)
      @testpath = nil
    end
    ret
  end

  def test_defined?
    not self.class.instance_variable_get(:@test_defined).nil?
  end

  private

  def stage
    fetched = fetch
    verify_download_integrity(fetched) if fetched.file?
    mktemp do
      downloader.stage
      # Set path after the downloader changes the working folder.
      @buildpath = Pathname.pwd
      yield
      @buildpath = nil
    end
  end

  def patch
    patch_list = Patches.new(patches)
    return if patch_list.empty?

    if patch_list.external_patches?
      ohai "Downloading patches"
      patch_list.download!
    end

    ohai "Patching"
    patch_list.each do |p|
      case p.compression
        when :gzip  then safe_system "/usr/bin/gunzip",  p.compressed_filename
        when :bzip2 then safe_system "/usr/bin/bunzip2", p.compressed_filename
      end
      # -f means don't prompt the user if there are errors; just exit with non-zero status
      safe_system '/usr/bin/patch', '-f', *(p.patch_args)
    end
  end

  def self.method_added method
    case method
    when :brew
      raise "You cannot override Formula#brew"
    when :test
      @test_defined = true
    end
  end

  class << self
    # The methods below define the formula DSL.

    def self.attr_rw(*attrs)
      attrs.each do |attr|
        class_eval <<-EOS, __FILE__, __LINE__ + 1
          def #{attr}(val=nil)
            val.nil? ? @#{attr} : @#{attr} = val
          end
        EOS
      end
    end

    attr_rw :homepage, :keg_only_reason, :skip_clean_all, :cc_failures
    attr_rw :plist_startup, :plist_manual

    Checksum::TYPES.each do |cksum|
      class_eval <<-EOS, __FILE__, __LINE__ + 1
        def #{cksum}(val)
          @stable ||= SoftwareSpec.new
          @stable.#{cksum}(val)
        end
      EOS
    end

    def build
      @build ||= BuildOptions.new(ARGV.options_only)
    end

    def url val, specs={}
      @stable ||= SoftwareSpec.new
      @stable.url(val, specs)
    end

    def stable &block
      return @stable unless block_given?
      instance_eval(&block)
    end

    def bottle *, &block
      return @bottle unless block_given?
      @bottle ||= Bottle.new
      @bottle.instance_eval(&block)
    end

    def devel &block
      return @devel unless block_given?
      @devel ||= SoftwareSpec.new
      @devel.instance_eval(&block)
    end

    def head val=nil, specs={}
      return @head if val.nil?
      @head ||= HeadSoftwareSpec.new
      @head.url(val, specs)
    end

    def version val=nil
      @stable ||= SoftwareSpec.new
      @stable.version(val)
    end

    def mirror val
      @stable ||= SoftwareSpec.new
      @stable.mirror(val)
    end

    def dependencies
      @dependencies ||= DependencyCollector.new
    end

    def depends_on dep
      d = dependencies.add(dep)
      post_depends_on(d) unless d.nil?
    end

    def option name, description=nil
      # Support symbols
      name = name.to_s
      raise "Option name is required." if name.empty?
      raise "Options should not start with dashes." if name[0, 1] == "-"
      build.add name, description
    end

    def plist_options options
      @plist_startup = options[:startup]
      @plist_manual = options[:manual]
    end

    def conflicts_with formula, opts={}
      dependencies.add ConflictRequirement.new(formula, name, opts)
    end

    def skip_clean *paths
      paths = [paths].flatten

      # :all is deprecated though
      if paths.include? :all
        @skip_clean_all = true
        return
      end

      @skip_clean_paths ||= []
      paths.each do |p|
        p = p.to_s unless p == :la # Keep :la in paths as a symbol
        @skip_clean_paths << p unless @skip_clean_paths.include? p
      end
    end

    def skip_clean_all?
      @skip_clean_all
    end

    def skip_clean_paths
      @skip_clean_paths or []
    end

    def keg_only reason, explanation=nil
      @keg_only_reason = KegOnlyReason.new(reason, explanation.to_s.chomp)
    end

    def fails_with compiler, &block
      @cc_failures ||= Set.new
      @cc_failures << CompilerFailure.new(compiler, &block)
    end

    def test &block
      return @test unless block_given?
      @test_defined = true
      @test = block
    end

    private

    def post_depends_on(dep)
      if dep.is_a? Array
        return dep.each {|d| post_depends_on(d)}
      end

      # Generate with- or without- options for optional and recommended
      # dependencies and requirements
      name = dep.name.split("/").last # strip any tap prefix
      if dep.optional? && !build.has_option?("with-#{name}")
        build.add("with-#{name}", "Build with #{name} support")
      elsif dep.recommended? && !build.has_option?("without-#{name}")
        build.add("without-#{name}", "Build without #{name} support")
      end
    end
  end
end

require 'formula_specialties'
