# This script is loaded by formula_installer as a separate instance.
# Thrown exceptions are propogated back to the parent process over a pipe

old_trap = trap("INT") { exit! 130 }

require "global"
require "build_options"
require "cxxstdlib"
require "keg"
require "extend/ENV"
require "debrew" if ARGV.debug?
require "fcntl"

class Build
  attr_reader :formula, :deps, :reqs

  def initialize(formula, options)
    @formula = formula
    @formula.build = BuildOptions.new(options, formula.options)

    if ARGV.ignore_deps?
      @deps = []
      @reqs = []
    else
      @deps = expand_deps
      @reqs = expand_reqs
    end
  end

  def post_superenv_hacks
    # Only allow Homebrew-approved directories into the PATH, unless
    # a formula opts-in to allowing the user's path.
    if formula.env.userpaths? || reqs.any? { |rq| rq.env.userpaths? }
      ENV.userpaths!
    end
  end

  def pre_superenv_hacks
    # Allow a formula to opt-in to the std environment.
    if (formula.env.std? || deps.any? { |d| d.name == "scons" }) && ARGV.env != "super"
      ARGV.unshift "--env=std"
    end
  end

  def effective_build_options_for(dependent)
    args  = dependent.build.used_options
    args |= Tab.for_formula(dependent).used_options
    BuildOptions.new(args, dependent.options)
  end

  def expand_reqs
    formula.recursive_requirements do |dependent, req|
      build = effective_build_options_for(dependent)
      if (req.optional? || req.recommended?) && build.without?(req)
        Requirement.prune
      elsif req.build? && dependent != formula
        Requirement.prune
      elsif req.satisfied? && req.default_formula? && (dep = req.to_dependency).installed?
        deps << dep
        Requirement.prune
      end
    end
  end

  def expand_deps
    formula.recursive_dependencies do |dependent, dep|
      build = effective_build_options_for(dependent)
      if (dep.optional? || dep.recommended?) && build.without?(dep)
        Dependency.prune
      elsif dep.build? && dependent != formula
        Dependency.prune
      elsif dep.build?
        Dependency.keep_but_prune_recursive_deps
      end
    end
  end

  def install
    keg_only_deps = deps.map(&:to_formula).select(&:keg_only?)

    deps.map(&:to_formula).each do |dep|
      fixopt(dep) unless dep.opt_prefix.directory?
    end

    pre_superenv_hacks
    ENV.activate_extensions!

    if superenv?
      ENV.keg_only_deps = keg_only_deps.map(&:name)
      ENV.deps = deps.map { |d| d.to_formula.name }
      ENV.x11 = reqs.any? { |rq| rq.kind_of?(X11Dependency) }
      ENV.setup_build_environment(formula)
      post_superenv_hacks
      reqs.each(&:modify_build_environment)
      deps.each(&:modify_build_environment)
    else
      ENV.setup_build_environment(formula)
      reqs.each(&:modify_build_environment)
      deps.each(&:modify_build_environment)

      keg_only_deps.each do |dep|
        ENV.prepend_path "PATH", dep.opt_bin.to_s
        ENV.prepend_path "PKG_CONFIG_PATH", "#{dep.opt_lib}/pkgconfig"
        ENV.prepend_path "PKG_CONFIG_PATH", "#{dep.opt_share}/pkgconfig"
        ENV.prepend_path "ACLOCAL_PATH", "#{dep.opt_share}/aclocal"
        ENV.prepend_path "CMAKE_PREFIX_PATH", dep.opt_prefix.to_s
        ENV.prepend "LDFLAGS", "-L#{dep.opt_lib}" if dep.opt_lib.directory?
        ENV.prepend "CPPFLAGS", "-I#{dep.opt_include}" if dep.opt_include.directory?
      end
    end

    formula.brew do
      if ARGV.flag? '--git'
        system "git", "init"
        system "git", "add", "-A"
      end
      if ARGV.interactive?
        ohai "Entering interactive mode"
        puts "Type `exit' to return and finalize the installation"
        puts "Install to this prefix: #{formula.prefix}"

        if ARGV.flag? '--git'
          puts "This directory is now a git repo. Make your changes and then use:"
          puts "  git diff | pbcopy"
          puts "to copy the diff to the clipboard."
        end

        interactive_shell(formula)
      else
        formula.prefix.mkpath

        formula.resources.each { |r| r.extend(ResourceDebugger) } if ARGV.debug?

        begin
          formula.install
        rescue Exception => e
          if ARGV.debug?
            debrew(e, formula)
          else
            raise
          end
        end

        stdlibs = detect_stdlibs
        Tab.create(formula, ENV.compiler, stdlibs.first, formula.build).write

        # Find and link metafiles
        formula.prefix.install_metafiles Pathname.pwd
      end
    end
  end

  def detect_stdlibs
    keg = Keg.new(formula.prefix)
    CxxStdlib.check_compatibility(formula, deps, keg, ENV.compiler)

    # The stdlib recorded in the install receipt is used during dependency
    # compatibility checks, so we only care about the stdlib that libraries
    # link against.
    keg.detect_cxx_stdlibs(:skip_executables => true)
  end

  def fixopt f
    path = if f.linked_keg.directory? and f.linked_keg.symlink?
      f.linked_keg.resolved_path
    elsif f.prefix.directory?
      f.prefix
    elsif (kids = f.rack.children).size == 1 and kids.first.directory?
      kids.first
    else
      raise
    end
    Keg.new(path).optlink
  rescue StandardError
    raise "#{f.opt_prefix} not present or broken\nPlease reinstall #{f}. Sorry :("
  end
end

begin
  error_pipe = IO.new(ENV["HOMEBREW_ERROR_PIPE"].to_i, "w")
  error_pipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

  # Invalidate the current sudo timestamp in case a build script calls sudo
  system "/usr/bin/sudo", "-k"

  trap("INT", old_trap)

  formula = ARGV.formulae.first
  options = Options.create(ARGV.flags_only)
  build   = Build.new(formula, options)
  build.install
rescue Exception => e
  e.continuation = nil if ARGV.debug?
  Marshal.dump(e, error_pipe)
  error_pipe.close
  exit! 1
end
