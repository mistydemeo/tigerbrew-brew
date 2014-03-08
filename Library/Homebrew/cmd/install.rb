require 'formula_installer'
require 'hardware'
require 'blacklist'

module Homebrew extend self
  def install
    raise FormulaUnspecifiedError if ARGV.named.empty?

    {
      'gcc' => 'gcc-4.2',
      'llvm' => 'llvm-gcc',
      'clang' => 'clang'
    }.each_pair do |old, new|
      opt = "--use-#{old}"
      if ARGV.include? opt then opoo <<-EOS.undent
        #{opt.inspect} is deprecated and will be removed in a future version.
        Please use "--cc=#{new}" instead.
        EOS
      end
    end

    if ARGV.include? '--head'
      raise "Specify `--HEAD` in uppercase to build from trunk."
    end

    ARGV.named.each do |name|
      # if a formula has been tapped ignore the blacklisting
      unless Formula.path(name).file?
        msg = blacklisted? name
        raise "No available formula for #{name}\n#{msg}" if msg
      end
      if not File.exist? name and name =~ HOMEBREW_TAP_FORMULA_REGEX then
        require 'cmd/tap'
        install_tap $1, $2
      end
    end unless ARGV.force?

    perform_preinstall_checks
    begin
      ARGV.formulae.each do |f|
        begin
          install_formula(f)
        rescue CannotInstallFormulaError => e
          ofail e.message
        end
      end
    rescue FormulaUnavailableError => e
      ofail e.message
      require 'cmd/search'
      puts 'Searching taps...'
      puts_columns(search_taps(query_regexp(e.name)))
    end
  end

  def check_writable_install_location
    raise "Cannot write to #{HOMEBREW_CELLAR}" if HOMEBREW_CELLAR.exist? and not HOMEBREW_CELLAR.writable_real?
    raise "Cannot write to #{HOMEBREW_PREFIX}" unless HOMEBREW_PREFIX.writable_real? or HOMEBREW_PREFIX.to_s == '/usr/local'
  end

  def check_xcode
    require 'cmd/doctor'
    checks = Checks.new
    doctor_methods = ['check_xcode_clt', 'check_xcode_license_approved',
                      'check_for_osx_gcc_installer']
    doctor_methods.each do |check|
      out = checks.send(check)
      opoo out unless out.nil?
    end
  end

  def check_macports
    unless MacOS.macports_or_fink.empty?
      opoo "It appears you have MacPorts or Fink installed."
      puts "Software installed with other package managers causes known problems for"
      puts "Tigerbrew. If a formula fails to build, uninstall MacPorts/Fink and try again."
    end
  end

  def check_cellar
    FileUtils.mkdir_p HOMEBREW_CELLAR if not File.exist? HOMEBREW_CELLAR
  rescue
    raise <<-EOS.undent
      Could not create #{HOMEBREW_CELLAR}
      Check you have permission to write to #{HOMEBREW_CELLAR.parent}
    EOS
  end

  def perform_preinstall_checks
    # check_ppc
    check_writable_install_location
    check_xcode
    check_macports
    check_cellar
  end

  def install_formula f
    fi = FormulaInstaller.new(f)
    fi.ignore_deps = ARGV.ignore_deps? || ARGV.interactive?
    fi.only_deps = ARGV.only_deps?
    fi.prelude
    fi.install
    fi.caveats
    fi.finish
  rescue FormulaInstallationAlreadyAttemptedError
    # We already attempted to install f as part of the dependency tree of
    # another formula. In that case, don't generate an error, just move on.
  rescue FormulaAlreadyInstalledError => e
    opoo e.message
  # Ignore CannotInstallFormulaError and let caller handle it.
  end
end
