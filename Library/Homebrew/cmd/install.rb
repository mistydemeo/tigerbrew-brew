require "blacklist"
require "cmd/doctor"
require "cmd/search"
require "cmd/tap"
require "formula_installer"
require "hardware"

module Homebrew
  def install
    raise FormulaUnspecifiedError if ARGV.named.empty?

    if ARGV.include? "--head"
      raise "Specify `--HEAD` in uppercase to build from trunk."
    end

    ARGV.named.each do |name|
      if !File.exist?(name) && (name !~ HOMEBREW_CORE_FORMULA_REGEX) \
              && (name =~ HOMEBREW_TAP_FORMULA_REGEX || name =~ HOMEBREW_CASK_TAP_FORMULA_REGEX)
        install_tap $1, $2
      end
    end unless ARGV.force?

    begin
      formulae = []

      if ARGV.casks.any?
        brew_cask = Formulary.factory("brew-cask")
        install_formula(brew_cask) unless brew_cask.installed?
        args = []
        args << "--force" if ARGV.force?
        args << "--debug" if ARGV.debug?
        args << "--verbose" if ARGV.verbose?

        ARGV.casks.each do |c|
          cmd = "brew", "cask", "install", c, *args
          ohai cmd.join " "
          system(*cmd)
        end
      end

      # if the user's flags will prevent bottle only-installations when no
      # developer tools are available, we need to stop them early on
      FormulaInstaller.prevent_build_flags unless MacOS.has_apple_developer_tools?

      ARGV.formulae.each do |f|
        # head-only without --HEAD is an error
        if !ARGV.build_head? && f.stable.nil? && f.devel.nil?
          raise <<-EOS.undent
          #{f.full_name} is a head-only formula
          Install with `brew install --HEAD #{f.full_name}`
          EOS
        end

        # devel-only without --devel is an error
        if !ARGV.build_devel? && f.stable.nil? && f.head.nil?
          raise <<-EOS.undent
          #{f.full_name} is a devel-only formula
          Install with `brew install --devel #{f.full_name}`
          EOS
        end

        if ARGV.build_stable? && f.stable.nil?
          raise "#{f.full_name} has no stable download, please choose --devel or --HEAD"
        end

        # --HEAD, fail with no head defined
        if ARGV.build_head? && f.head.nil?
          raise "No head is defined for #{f.full_name}"
        end

        # --devel, fail with no devel defined
        if ARGV.build_devel? && f.devel.nil?
          raise "No devel block is defined for #{f.full_name}"
        end

        if f.installed?
          msg = "#{f.full_name}-#{f.installed_version} already installed"
          msg << ", it's just not linked" unless f.linked_keg.symlink? || f.keg_only?
          opoo msg
        elsif f.oldname && (dir = HOMEBREW_CELLAR/f.oldname).exist? && !dir.subdirs.empty? \
            && f.tap == Tab.for_keg(dir.subdirs.first).tap && !ARGV.force?
          # Check if the formula we try to install is the same as installed
          # but not migrated one. If --force passed then install anyway.
          opoo "#{f.oldname} already installed, it's just not migrated"
          puts "You can migrate formula with `brew migrate #{f}`"
          puts "Or you can force install it with `brew install #{f} --force`"
        else
          formulae << f
        end
      end

      perform_preinstall_checks

      formulae.each { |f| install_formula(f) }
    rescue FormulaUnavailableError => e
      if (blacklist = blacklisted?(e.name))
        ofail "#{e.message}\n#{blacklist}"
      else
        ofail e.message
        query = query_regexp(e.name)
        ohai "Searching formulae..."
        puts_columns(search_formulae(query))
        ohai "Searching taps..."
        puts_columns(search_taps(query))

        # If they haven't updated in 48 hours (172800 seconds), that
        # might explain the error
        master = HOMEBREW_REPOSITORY/".git/refs/heads/master"
        if master.exist? && (Time.now.to_i - File.mtime(master).to_i) > 172800
          ohai "You haven't updated Homebrew in a while."
          puts <<-EOS.undent
            A formula for #{e.name} might have been added recently.
            Run `brew update` to get the latest Homebrew updates!
          EOS
        end
      end
    end
  end

  def check_writable_install_location
    raise "Cannot write to #{HOMEBREW_CELLAR}" if HOMEBREW_CELLAR.exist? && !HOMEBREW_CELLAR.writable_real?
    raise "Cannot write to #{HOMEBREW_PREFIX}" unless HOMEBREW_PREFIX.writable_real? || HOMEBREW_PREFIX.to_s == "/usr/local"
  end

  def check_xcode
    checks = Checks.new
    %w[
      check_for_unsupported_osx
      check_for_bad_install_name_tool
      check_for_installed_developer_tools
      check_xcode_license_approved
      check_for_osx_gcc_installer
    ].each do |check|
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
    FileUtils.mkdir_p HOMEBREW_CELLAR unless File.exist? HOMEBREW_CELLAR
  rescue
    raise <<-EOS.undent
      Could not create #{HOMEBREW_CELLAR}
      Check you have permission to write to #{HOMEBREW_CELLAR.parent}
    EOS
  end

  def perform_preinstall_checks
    # check_ppc
    check_writable_install_location
    check_xcode if MacOS.has_apple_developer_tools?
    check_cellar
  end

  def install_formula(f)
    f.print_tap_action

    fi = FormulaInstaller.new(f)
    fi.options             = f.build.used_options
    fi.ignore_deps         = ARGV.ignore_deps?
    fi.only_deps           = ARGV.only_deps?
    fi.build_bottle        = ARGV.build_bottle?
    fi.build_from_source   = ARGV.build_from_source?
    fi.force_bottle        = ARGV.force_bottle?
    fi.interactive         = ARGV.interactive?
    fi.git                 = ARGV.git?
    fi.verbose             = ARGV.verbose?
    fi.quieter             = ARGV.quieter?
    fi.debug               = ARGV.debug?
    fi.prelude
    fi.install
    fi.finish
  rescue FormulaInstallationAlreadyAttemptedError
    # We already attempted to install f as part of the dependency tree of
    # another formula. In that case, don't generate an error, just move on.
  rescue CannotInstallFormulaError => e
    ofail e.message
  rescue BuildError
    check_macports
    raise
  end
end
