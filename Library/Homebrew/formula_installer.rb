# encoding: UTF-8

require 'exceptions'
require 'formula'
require 'keg'
require 'tab'
require 'bottles'
require 'caveats'

class FormulaInstaller
  attr_reader :f
  attr_accessor :tab, :options, :ignore_deps
  attr_accessor :show_summary_heading, :show_header

  def initialize ff
    @f = ff
    @show_header = false
    @ignore_deps = ARGV.ignore_deps? || ARGV.interactive?
    @options = Options.new
    @tab = Tab.dummy_tab(ff)

    @@attempted ||= Set.new

    lock
    check_install_sanity
  end

  def pour_bottle? warn=false
    tab.used_options.empty? && options.empty? && install_bottle?(f, warn)
  end

  def check_install_sanity
    raise FormulaInstallationAlreadyAttemptedError, f if @@attempted.include? f

    if f.installed?
      msg = "#{f}-#{f.installed_version} already installed"
      msg << ", it's just not linked" if not f.linked_keg.symlink? and not f.keg_only?
      raise FormulaAlreadyInstalledError, msg
    end

    # Building head-only without --HEAD is an error
    if not ARGV.build_head? and f.stable.nil?
      raise CannotInstallFormulaError, <<-EOS.undent
        #{f} is a head-only formula
        Install with `brew install --HEAD #{f.name}
      EOS
    end

    # Building stable-only with --HEAD is an error
    if ARGV.build_head? and f.head.nil?
      raise CannotInstallFormulaError, "No head is defined for #{f.name}"
    end

    unless ignore_deps
      unlinked_deps = f.recursive_dependencies.map(&:to_formula).select do |dep|
        dep.installed? and not dep.keg_only? and not dep.linked_keg.directory?
      end
      raise CannotInstallFormulaError,
        "You must `brew link #{unlinked_deps*' '}' before #{f} can be installed" unless unlinked_deps.empty?
    end

  rescue FormulaUnavailableError => e
    # this is sometimes wrong if the dependency chain is more than one deep
    # but can't easily fix this without a rewrite FIXME-brew2
    e.dependent = f.name
    raise
  end

  def install
    # not in initialize so upgrade can unlink the active keg before calling this
    # function but after instantiating this class so that it can avoid having to
    # relink the active keg if possible (because it is slow).
    if f.linked_keg.directory?
      # some other version is already installed *and* linked
      raise CannotInstallFormulaError, <<-EOS.undent
        #{f}-#{f.linked_keg.realpath.basename} already installed
        To install this version, first `brew unlink #{f}'
      EOS
    end

    unless ignore_deps
      # HACK: If readline is present in the dependency tree, it will clash
      # with the stdlib's Readline module when the debugger is loaded
      if f.recursive_deps.any? { |d| d.name == "readline" } and ARGV.debug?
        ENV['HOMEBREW_NO_READLINE'] = '1'
      end

      check_requirements
      install_dependencies
    end

    oh1 "Installing #{Tty.green}#{f}#{Tty.reset}" if show_header

    @@attempted << f

    @poured_bottle = false
    begin
      if pour_bottle? true
        pour
        @poured_bottle = true
        tab = Tab.for_keg f.prefix
        tab.poured_from_bottle = true
        tab.tabfile.delete rescue nil
        tab.write
      end
    rescue
      opoo "Bottle installation failed: building from source."
    end

    unless @poured_bottle
      build
      clean
    end

    f.post_install

    opoo "Nothing was installed to #{f.prefix}" unless f.installed?
  end

  def check_requirements
    unsatisfied = ARGV.filter_for_dependencies do
      f.recursive_requirements do |dependent, req|
        if req.optional? || req.recommended?
          Requirement.prune unless dependent.build.with?(req.name)
        elsif req.build?
          Requirement.prune if install_bottle?(dependent)
        end

        Requirement.prune if req.satisfied?
      end
    end

    unless unsatisfied.empty?
      puts unsatisfied.map(&:message) * "\n"
      fatals = unsatisfied.select(&:fatal?)
      raise UnsatisfiedRequirements.new(f, fatals) unless fatals.empty?
    end
  end

  def effective_deps
    @deps ||= begin
      deps = Set.new

      # If a dep was also requested on the command line, we let it honor
      # any influential flags (--HEAD, --devel, etc.) the user has passed
      # when we check the installed status.
      requested_deps = f.recursive_dependencies.select do |dep|
        dep.requested? && !dep.installed?
      end

      # Otherwise, we filter these influential flags so that they do not
      # affect installation prefixes and other properties when we decide
      # whether or not the dep is needed.
      necessary_deps = ARGV.filter_for_dependencies do
        f.recursive_dependencies do |dependent, dep|
          if dep.optional? || dep.recommended?
            Dependency.prune unless dependent.build.with?(dep.name)
          elsif dep.build?
            Dependency.prune if install_bottle?(dependent)
          end

          if f.build.universal?
            dep.universal! unless dep.build?
          end

          if dep.satisfied?
            Dependency.prune
          elsif dep.installed?
            raise UnsatisfiedDependencyError.new(f, dep)
          end
        end
      end

      deps.merge(requested_deps)
      deps.merge(necessary_deps)

      # Now that we've determined which deps we need, map them back
      # onto recursive_dependencies to preserve installation order
      f.recursive_dependencies.select { |d| deps.include? d }
    end
  end

  def install_dependencies
    effective_deps.each do |dep|
      if dep.requested?
       install_dependency(dep)
      else
        ARGV.filter_for_dependencies { install_dependency(dep) }
      end
    end
    @show_header = true unless effective_deps.empty?
  end

  def install_dependency dep
    dep_tab = Tab.for_formula(dep)
    dep_options = dep.options
    dep = dep.to_formula

    outdated_keg = Keg.new(dep.linked_keg.realpath) rescue nil

    fi = FormulaInstaller.new(dep)
    fi.tab = dep_tab
    fi.options = dep_options
    fi.ignore_deps = true
    fi.show_header = false
    oh1 "Installing #{f} dependency: #{Tty.green}#{dep}#{Tty.reset}"
    outdated_keg.unlink if outdated_keg
    fi.install
    fi.caveats
    fi.finish
  ensure
    # restore previous installation state if build failed
    outdated_keg.link if outdated_keg and not dep.installed? rescue nil
  end

  def caveats
    if (not f.keg_only?) and ARGV.homebrew_developer?
      audit_bin
      audit_sbin
      audit_lib
      check_manpages
      check_infopages
    end

    c = Caveats.new(f)

    unless c.empty?
      @show_summary_heading = true
      ohai 'Caveats', c.caveats
    end
  end

  def finish
    ohai 'Finishing up' if ARGV.verbose?

    if f.keg_only?
      begin
        Keg.new(f.prefix).optlink
      rescue Exception
        onoe "Failed to create: #{f.opt_prefix}"
        puts "Things that depend on #{f} will probably not build."
      end
    else
      link
      check_PATH unless f.keg_only?
    end

    install_plist
    fix_install_names

    ohai "Summary" if ARGV.verbose? or show_summary_heading
    unless ENV['HOMEBREW_NO_EMOJI']
      print "🍺  " if MacOS.version >= :lion
    end
    print "#{f.prefix}: #{f.prefix.abv}"
    print ", built in #{pretty_duration build_time}" if build_time
    puts

    unlock if hold_locks?
  end

  def build_time
    @build_time ||= Time.now - @start_time unless pour_bottle? or ARGV.interactive? or @start_time.nil?
  end

  def build_argv
    @build_argv ||= begin
      opts = Options.coerce(ARGV.options_only)
      unless opts.include? '--fresh'
        opts.concat(options) # from a dependent formula
        opts.concat(tab.used_options) # from a previous install
      end
      opts << Option.new("--build-from-source") # don't download bottle
    end
  end

  def build
    FileUtils.rm Dir["#{HOMEBREW_LOGS}/#{f}/*"]

    @start_time = Time.now

    # 1. formulae can modify ENV, so we must ensure that each
    #    installation has a pristine ENV when it starts, forking now is
    #    the easiest way to do this
    # 2. formulae have access to __END__ the only way to allow this is
    #    to make the formula script the executed script
    read, write = IO.pipe
    # I'm guessing this is not a good way to do this, but I'm no UNIX guru
    ENV['HOMEBREW_ERROR_PIPE'] = write.to_i.to_s

    args = %W[
      nice #{RUBY_PATH}
      -W0
      -I #{File.dirname(__FILE__)}
      -rbuild
      --
      #{f.path}
    ].concat(build_argv)

    # Ruby 2.0+ sets close-on-exec on all file descriptors except for
    # 0, 1, and 2 by default, so we have to specify that we want the pipe
    # to remain open in the child process.
    args << { write => write } if RUBY_VERSION >= "2.0"

    fork do
      begin
        read.close
        exec(*args)
      rescue Exception => e
        Marshal.dump(e, write)
        write.close
        exit! 1
      end
    end

    ignore_interrupts(:quietly) do # the fork will receive the interrupt and marshall it back
      write.close
      Process.wait
      data = read.read
      raise Marshal.load(data) unless data.nil? or data.empty?
      raise Interrupt if $?.exitstatus == 130
      raise "Suspicious installation failure" unless $?.success?
    end

    raise "Empty installation" if Dir["#{f.prefix}/*"].empty?

    Tab.create(f, build_argv).write # INSTALL_RECEIPT.json

  rescue Exception
    ignore_interrupts do
      # any exceptions must leave us with nothing installed
      f.prefix.rmtree if f.prefix.directory?
      f.rack.rmdir_if_possible
    end
    raise
  end

  def link
    if f.linked_keg.directory? and f.linked_keg.realpath == f.prefix
      opoo "This keg was marked linked already, continuing anyway"
      # otherwise Keg.link will bail
      f.linked_keg.unlink
    end

    keg = Keg.new(f.prefix)

    begin
      keg.link
    rescue Exception => e
      onoe "The `brew link` step did not complete successfully"
      puts "The formula built, but is not symlinked into #{HOMEBREW_PREFIX}"
      puts "You can try again using `brew link #{f.name}'"
      ohai e, e.backtrace if ARGV.debug?
      @show_summary_heading = true
      ignore_interrupts{ keg.unlink }
      raise unless e.kind_of? RuntimeError
    end
  end

  def install_plist
    return unless f.plist
    # A plist may already exist if we are installing from a bottle
    f.plist_path.unlink if f.plist_path.exist?
    f.plist_path.write f.plist
    f.plist_path.chmod 0644
  end

  def fix_install_names
    Keg.new(f.prefix).fix_install_names
    if @poured_bottle and f.bottle
      old_prefix = f.bottle.prefix
      new_prefix = HOMEBREW_PREFIX.to_s
      old_cellar = f.bottle.cellar
      new_cellar = HOMEBREW_CELLAR.to_s

      if old_prefix != new_prefix or old_cellar != new_cellar
        Keg.new(f.prefix).relocate_install_names \
          old_prefix, new_prefix, old_cellar, new_cellar
      end
    end
  rescue Exception => e
    onoe "Failed to fix install names"
    puts "The formula built, but you may encounter issues using it or linking other"
    puts "formula against it."
    ohai e, e.backtrace if ARGV.debug?
    @show_summary_heading = true
  end

  def clean
    ohai "Cleaning" if ARGV.verbose?
    if f.class.skip_clean_all?
      opoo "skip_clean :all is deprecated"
      puts "Skip clean was commonly used to prevent brew from stripping binaries."
      puts "brew no longer strips binaries, if skip_clean is required to prevent"
      puts "brew from removing empty directories, you should specify exact paths"
      puts "in the formula."
      return
    end
    require 'cleaner'
    Cleaner.new f
  rescue Exception => e
    opoo "The cleaning step did not complete successfully"
    puts "Still, the installation was successful, so we will link it into your prefix"
    ohai e, e.backtrace if ARGV.debug?
    @show_summary_heading = true
  end

  def pour
    fetched, downloader = f.fetch
    f.verify_download_integrity fetched unless downloader.local_bottle_path
    HOMEBREW_CELLAR.cd do
      downloader.stage
    end
  end

  ## checks

  def check_PATH
    # warn the user if stuff was installed outside of their PATH
    [f.bin, f.sbin].each do |bin|
      if bin.directory? and bin.children.length > 0
        bin = (HOMEBREW_PREFIX/bin.basename).realpath
        unless ORIGINAL_PATHS.include? bin
          opoo "#{bin} is not in your PATH"
          puts "You can amend this by altering your ~/.bashrc file"
          @show_summary_heading = true
        end
      end
    end
  end

  def check_manpages
    # Check for man pages that aren't in share/man
    if (f.prefix+'man').directory?
      opoo 'A top-level "man" directory was found.'
      puts "Tigerbrew requires that man pages live under share."
      puts 'This can often be fixed by passing "--mandir=#{man}" to configure.'
      @show_summary_heading = true
    end
  end

  def check_infopages
    # Check for info pages that aren't in share/info
    if (f.prefix+'info').directory?
      opoo 'A top-level "info" directory was found.'
      puts "Tigerbrew suggests that info pages live under share."
      puts 'This can often be fixed by passing "--infodir=#{info}" to configure.'
      @show_summary_heading = true
    end
  end

  def check_jars
    return unless f.lib.directory?

    jars = f.lib.children.select{|g| g.to_s =~ /\.jar$/}
    unless jars.empty?
      opoo 'JARs were installed to "lib".'
      puts "Installing JARs to \"lib\" can cause conflicts between packages."
      puts "For Java software, it is typically better for the formula to"
      puts "install to \"libexec\" and then symlink or wrap binaries into \"bin\"."
      puts "See \"activemq\", \"jruby\", etc. for examples."
      puts "The offending files are:"
      puts jars
      @show_summary_heading = true
    end
  end

  def check_non_libraries
    return unless f.lib.directory?

    valid_extensions = %w(.a .dylib .framework .jnilib .la .o .so
                          .jar .prl .pm .sh)
    non_libraries = f.lib.children.select do |g|
      next if g.directory?
      not valid_extensions.include? g.extname
    end

    unless non_libraries.empty?
      opoo 'Non-libraries were installed to "lib".'
      puts "Installing non-libraries to \"lib\" is bad practice."
      puts "The offending files are:"
      puts non_libraries
      @show_summary_heading = true
    end
  end

  def audit_bin
    return unless f.bin.directory?

    non_exes = f.bin.children.select { |g| g.directory? or not g.executable? }

    unless non_exes.empty?
      opoo 'Non-executables were installed to "bin".'
      puts "Installing non-executables to \"bin\" is bad practice."
      puts "The offending files are:"
      puts non_exes
      @show_summary_heading = true
    end
  end

  def audit_sbin
    return unless f.sbin.directory?

    non_exes = f.sbin.children.select { |g| g.directory? or not g.executable? }

    unless non_exes.empty?
      opoo 'Non-executables were installed to "sbin".'
      puts "Installing non-executables to \"sbin\" is bad practice."
      puts "The offending files are:"
      puts non_exes
      @show_summary_heading = true
    end
  end

  def audit_lib
    check_jars
    check_non_libraries
  end

  private

  def hold_locks?
    @hold_locks || false
  end

  def lock
    # ruby 1.8.2 doesn't implement flock
    # TODO backport the flock feature and reenable it
    return if MacOS.version == :tiger

    if (@@locked ||= []).empty?
      f.recursive_dependencies.each do |dep|
        @@locked << dep.to_formula
      end unless ignore_deps
      @@locked.unshift(f)
      @@locked.each(&:lock)
      @hold_locks = true
    end
  end

  def unlock
    if hold_locks?
      @@locked.each(&:unlock)
      @@locked.clear
      @hold_locks = false
    end
  end
end


class Formula
  def keg_only_text
    s = "This formula is keg-only: so it was not symlinked into #{HOMEBREW_PREFIX}."
    s << "\n\n#{keg_only_reason.to_s}"
    if lib.directory? or include.directory?
      s <<
        <<-EOS.undent_________________________________________________________72


        Generally there are no consequences of this for you. If you build your
        own software and it requires this formula, you'll need to add to your
        build variables:

        EOS
      s << "    LDFLAGS:  -L#{HOMEBREW_PREFIX}/opt/#{name}/lib\n" if lib.directory?
      s << "    CPPFLAGS: -I#{HOMEBREW_PREFIX}/opt/#{name}/include\n" if include.directory?
    end
    s << "\n"
  end
end
