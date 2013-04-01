require 'formula'
require 'tab'
require 'keg'
require 'caveats'

module Homebrew extend self
  def info
    # eventually we'll solidify an API, but we'll keep old versions
    # awhile around for compatibility
    if ARGV.json == "v1"
      print_json
    elsif ARGV.flag? '--github'
      exec_browser(*ARGV.formulae.map { |f| github_info(f) })
    else
      print_info
    end
  end

  def print_info
    if ARGV.named.empty?
      if ARGV.include? "--all"
        Formula.each do |f|
          info_formula f
          puts '---'
        end
      else
        puts "#{HOMEBREW_CELLAR.children.length} kegs, #{HOMEBREW_CELLAR.abv}"
      end
    elsif valid_url ARGV[0]
      info_formula Formula.factory(ARGV.shift)
    else
      ARGV.formulae.each{ |f| info_formula f }
    end
  end

  def print_json
    require 'vendor/multi_json'

    formulae = ARGV.include?("--all") ? Formula : ARGV.formulae
    json = formulae.map {|f| f.to_hash}
    if json.size == 1
      puts MultiJson.encode json.pop
    else
      puts MultiJson.encode json
    end
  end

  def github_fork
    if which 'git' and (HOMEBREW_REPOSITORY/".git").directory?
      if `git remote -v` =~ %r{origin\s+(https?://|git(?:@|://))github.com[:/](.+)/homebrew}
        $2
      end
    end
  end

  def github_info f
    path = f.path.realpath

    if path.to_s =~ %r{#{HOMEBREW_REPOSITORY}/Library/Taps/(\w+)-(\w+)/(.*)}
      user = $1
      repo = "homebrew-#$2"
      path = $3
    else
      path.parent.cd do
        user = github_fork
      end
      repo = "homebrew"
      path = "Library/Formula/#{path.basename}"
    end

    "https://github.com/#{user}/#{repo}/commits/master/#{path}"
  end

  def info_formula f
    specs = []
    stable = "stable #{f.stable.version}" if f.stable
    stable += " (bottled)" if f.bottle
    specs << stable if stable
    specs << "devel #{f.devel.version}" if f.devel
    specs << "HEAD" if f.head

    puts "#{f.name}: #{specs*', '}#{' (pinned)' if f.pinned?}"

    puts f.homepage

    if f.keg_only?
      puts
      puts "This formula is keg-only."
      puts f.keg_only_reason
      puts
    end

    puts "Depends on: #{f.deps*', '}" unless f.deps.empty?
    conflicts = f.conflicts.map { |c| c.formula }.sort
    puts "Conflicts with: #{conflicts*', '}" unless conflicts.empty?

    if f.rack.directory?
      kegs = f.rack.children
      kegs.reject! {|keg| keg.basename.to_s == '.DS_Store' }
      kegs = kegs.map {|keg| Keg.new(keg) }.sort_by {|keg| keg.version }
      kegs.each do |keg|
        puts "#{keg} (#{keg.abv})#{' *' if keg.linked?}"
        tab = Tab.for_keg(keg).to_s
        puts "  #{tab}" unless tab.empty?
      end
    else
      puts "Not installed"
    end

    history = github_info(f)
    puts history if history

    unless f.build.empty?
      require 'cmd/options'
      ohai "Options"
      Homebrew.dump_options_for_formula f
    end

    c = Caveats.new(f)
    ohai 'Caveats', c.caveats unless c.empty?

  rescue FormulaUnavailableError
    # check for DIY installation
    d = HOMEBREW_PREFIX+name
    if d.directory?
      ohai "DIY Installation"
      d.children.each{ |keg| puts "#{keg} (#{keg.abv})" }
    else
      raise "No such formula or keg"
    end
  end

  private

  def valid_url u
    u[0..6] == 'http://' or u[0..7] == 'https://' or u[0..5] == 'ftp://'
  end

end
