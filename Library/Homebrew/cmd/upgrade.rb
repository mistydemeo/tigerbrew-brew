require 'cmd/install'
require 'cmd/outdated'

module Homebrew
  def upgrade
    Homebrew.perform_preinstall_checks

    if ARGV.include?("--all") || ARGV.named.empty?
      unless ARGV.include? "--all"
        opoo <<-EOS.undent
          brew upgrade with no arguments will change behaviour soon!
          It currently upgrades all formula but this will soon change to require '--all'.
          Please update any workflows, documentation and scripts!
        EOS
      end
      outdated = Homebrew.outdated_brews(Formula.installed)
      exit 0 if outdated.empty?
    elsif ARGV.named.any?
      outdated = Homebrew.outdated_brews(ARGV.formulae)

      (ARGV.formulae - outdated).each do |f|
        if f.rack.directory?
          version = f.rack.subdirs.map { |d| Keg.new(d).version }.max
          onoe "#{f.name} #{version} already installed"
        else
          onoe "#{f.name} not installed"
        end
      end
      exit 1 if outdated.empty?
    else
      # This will currently never be reached but is implemented to make the
      # migration to --all easier in the future (as just the ARGV.named.empty?
      # will need removed above).
      odie "Either --all or one or more formulae must be specified!"
    end

    unless upgrade_pinned?
      pinned = outdated.select(&:pinned?)
      outdated -= pinned
    end

    unless outdated.empty?
      oh1 "Upgrading #{outdated.length} outdated package#{plural(outdated.length)}, with result:"
      puts outdated.map{ |f| "#{f.name} #{f.pkg_version}" } * ", "
    else
      oh1 "No packages to upgrade"
    end

    unless upgrade_pinned? || pinned.empty?
      oh1 "Not upgrading #{pinned.length} pinned package#{plural(pinned.length)}:"
      puts pinned.map{ |f| "#{f.name} #{f.pkg_version}" } * ", "
    end

    outdated.each { |f| upgrade_formula(f) }
  end

  def upgrade_pinned?
    not ARGV.named.empty?
  end

  def upgrade_formula f
    outdated_keg = Keg.new(f.linked_keg.resolved_path) if f.linked_keg.directory?
    tab = Tab.for_formula(f)

    fi = FormulaInstaller.new(f)
    fi.options             = tab.used_options
    fi.build_bottle        = ARGV.build_bottle? || (!f.bottled? && tab.build_bottle?)
    fi.build_from_source   = ARGV.build_from_source?
    fi.verbose             = ARGV.verbose?
    fi.quieter             = ARGV.quieter?
    fi.debug               = ARGV.debug?
    fi.prelude

    oh1 "Upgrading #{f.name}"

    # first we unlink the currently active keg for this formula otherwise it is
    # possible for the existing build to interfere with the build we are about to
    # do! Seriously, it happens!
    outdated_keg.unlink if outdated_keg

    fi.install
    fi.caveats
    fi.finish

    # If the formula was pinned, and we were force-upgrading it, unpin and
    # pin it again to get a symlink pointing to the correct keg.
    if f.pinned?
      f.unpin
      f.pin
    end
  rescue FormulaInstallationAlreadyAttemptedError
    # We already attempted to upgrade f as part of the dependency tree of
    # another formula. In that case, don't generate an error, just move on.
  rescue CannotInstallFormulaError => e
    ofail e
  rescue BuildError => e
    e.dump
    puts
    Homebrew.failed = true
  rescue DownloadError => e
    ofail e
  ensure
    # restore previous installation state if build failed
    outdated_keg.link if outdated_keg and not f.installed? rescue nil
  end

end
