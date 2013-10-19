require 'os/mac'
require 'extend/ENV/shared'

### Why `superenv`?
# 1) Only specify the environment we need (NO LDFLAGS for cmake)
# 2) Only apply compiler specific options when we are calling that compiler
# 3) Force all incpaths and libpaths into the cc instantiation (less bugs)
# 4) Cater toolchain usage to specific Xcode versions
# 5) Remove flags that we don't want or that will break builds
# 6) Simpler code
# 7) Simpler formula that *just work*
# 8) Build-system agnostic configuration of the tool-chain

module Superenv
  include SharedEnvExtension

  attr_accessor :keg_only_deps, :deps, :x11
  alias_method :x11?, :x11

  def self.extended(base)
    base.keg_only_deps = []
    base.deps = []

    # Many formula assume that CFLAGS etc. will not be nil. This should be
    # a safe hack to prevent that exception cropping up. Main consequence of
    # this is that self['CFLAGS'] is never nil even when it is which can break
    # if checks, but we don't do such a check in our code. Redefinition must be
    # done on the singleton class, because in MRI all ENV methods are defined
    # on its singleton class, precluding the use of extend.
    class << base
      def [] key
        if has_key? key
          fetch(key)
        elsif %w{CPPFLAGS CFLAGS LDFLAGS}.include? key
          self[key] = ""
        end
      end
    end
  end

  def self.bin
    @bin ||= (HOMEBREW_REPOSITORY/"Library/ENV").children.reject{|d| d.basename.to_s > MacOS::Xcode.version }.max
  end

  def reset
    %w{CC CXX OBJC OBJCXX CPP MAKE LD LDSHARED
      CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS LDFLAGS CPPFLAGS
      MACOS_DEPLOYMENT_TARGET SDKROOT
      CMAKE_PREFIX_PATH CMAKE_INCLUDE_PATH CMAKE_FRAMEWORK_PATH
      CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH}.
      each{ |x| delete(x) }
    delete('CDPATH') # avoid make issues that depend on changing directories
    delete('GREP_OPTIONS') # can break CMake
    delete('CLICOLOR_FORCE') # autotools doesn't like this
  end

  def setup_build_environment(formula=nil)
    reset

    self.cc  = 'cc'
    self.cxx = 'c++'
    self['HOMEBREW_CC'] = determine_cc
    validate_cc!(formula) unless formula.nil?
    self['DEVELOPER_DIR'] = determine_developer_dir
    self['MAKEFLAGS'] ||= "-j#{determine_make_jobs}"
    self['PATH'] = determine_path
    self['PKG_CONFIG_PATH'] = determine_pkg_config_path
    self['PKG_CONFIG_LIBDIR'] = determine_pkg_config_libdir
    self['HOMEBREW_CCCFG'] = determine_cccfg
    self['HOMEBREW_BREW_FILE'] = HOMEBREW_BREW_FILE
    self['HOMEBREW_SDKROOT'] = "#{MacOS.sdk_path}" if MacOS::Xcode.without_clt?
    self['HOMEBREW_DEVELOPER_DIR'] = determine_developer_dir # used by our xcrun shim
    self['HOMEBREW_VERBOSE'] = "1" if ARGV.verbose?
    self['CMAKE_PREFIX_PATH'] = determine_cmake_prefix_path
    self['CMAKE_FRAMEWORK_PATH'] = determine_cmake_frameworks_path
    self['CMAKE_INCLUDE_PATH'] = determine_cmake_include_path
    self['CMAKE_LIBRARY_PATH'] = determine_cmake_library_path
    self['ACLOCAL_PATH'] = determine_aclocal_path

    # For custom bottles, need to specify the arch in the environment
    # so that the compiler shims have access
    if (arch = ARGV.bottle_arch)
      self['HOMEBREW_ARCHFLAGS'] = Hardware::CPU.optimization_flags[arch]
    end

    # The HOMEBREW_CCCFG ENV variable is used by the ENV/cc tool to control
    # compiler flag stripping. It consists of a string of characters which act
    # as flags. Some of these flags are mutually exclusive.
    #
    # u - A universal build was requested
    # 3 - A 32-bit build was requested
    # b - Installing from a bottle
    # c - Installing from a bottle with a custom architecture
    # i - Installing from a bottle on Intel
    # 6 - Installing from a bottle on 64-bit Intel
    # p - Installing from a bottle on PPC
    # A - Installing from a bottle on PPC with Altivec
    # O - Enables argument refurbishing. Only active under the
    #     make/bsdmake wrappers currently.
    #
    # On 10.8 and newer, these flags will also be present:
    # s - apply fix for sed's Unicode support
    # a - apply fix for apr-1-config path

    warn_about_non_apple_gcc($1) if ENV['HOMEBREW_CC'] =~ GNU_GCC_REGEXP
  end

  def universal_binary
    self['HOMEBREW_ARCHS'] = Hardware::CPU.universal_archs.join(',')
    append 'HOMEBREW_CCCFG', "u", ''
  end

  # m32 on superenv does not add any CC flags. It prevents "-m32" from being erased.
  def m32
    append 'HOMEBREW_CCCFG', "3", ''
  end

  private

  def determine_cc
    cc = compiler
    COMPILER_SYMBOL_MAP.invert.fetch(cc, cc)
  end

  def determine_path
    paths = [Superenv.bin]
    if MacOS::Xcode.without_clt?
      paths << "#{MacOS::Xcode.prefix}/usr/bin"
      paths << "#{MacOS::Xcode.prefix}/Toolchains/XcodeDefault.xctoolchain/usr/bin"
    end
    paths += deps.map{|dep| "#{HOMEBREW_PREFIX}/opt/#{dep}/bin" }
    paths << MacOS::X11.bin if x11?
    paths += %w{/usr/bin /bin /usr/sbin /sbin}

    # Homebrew's apple-gcc42 will be outside the PATH in superenv,
    # so xcrun may not be able to find it
    if self['HOMEBREW_CC'] == 'gcc-4.2'
      apple_gcc42 = begin
        Formulary.factory('apple-gcc42')
      rescue Exception # in --debug, catch bare exceptions too
        nil
      end
      paths << apple_gcc42.opt_prefix/'bin' if apple_gcc42
    end

    if self['HOMEBREW_CC'] =~ GNU_GCC_REGEXP
      gcc_name = 'gcc' + $1.delete('.')
      gcc = Formulary.factory(gcc_name)
      paths << gcc.opt_prefix/'bin'
    end

    paths.to_path_s
  end

  def determine_pkg_config_path
    paths  = deps.map{|dep| "#{HOMEBREW_PREFIX}/opt/#{dep}/lib/pkgconfig" }
    paths += deps.map{|dep| "#{HOMEBREW_PREFIX}/opt/#{dep}/share/pkgconfig" }
    paths.to_path_s
  end

  def determine_pkg_config_libdir
    paths = %W{/usr/lib/pkgconfig #{HOMEBREW_REPOSITORY}/Library/ENV/pkgconfig/#{MacOS.version}}
    paths << "#{MacOS::X11.lib}/pkgconfig" << "#{MacOS::X11.share}/pkgconfig" if x11?
    paths.to_path_s
  end

  def determine_cmake_prefix_path
    paths = keg_only_deps.map{|dep| "#{HOMEBREW_PREFIX}/opt/#{dep}" }
    paths << HOMEBREW_PREFIX.to_s # put ourselves ahead of everything else
    paths << "#{MacOS.sdk_path}/usr" if MacOS::Xcode.without_clt?
    paths.to_path_s
  end

  def determine_cmake_frameworks_path
    # XXX: keg_only_deps perhaps? but Qt does not link its Frameworks because of Ruby's Find.find ignoring symlinks!!
    paths = deps.map{|dep| "#{HOMEBREW_PREFIX}/opt/#{dep}/Frameworks" }
    paths << "#{MacOS.sdk_path}/System/Library/Frameworks" if MacOS::Xcode.without_clt?
    paths.to_path_s
  end

  def determine_cmake_include_path
    sdk = MacOS.sdk_path if MacOS::Xcode.without_clt?
    paths = []
    paths << "#{MacOS::X11.include}/freetype2" if x11?
    paths << "#{sdk}/usr/include/libxml2" unless deps.include? 'libxml2'
    paths << "#{sdk}/usr/include/apache2" if MacOS::Xcode.without_clt?
    paths << "#{sdk}/System/Library/Frameworks/OpenGL.framework/Versions/Current/Headers" unless x11?
    paths << MacOS::X11.include if x11?
    paths.to_path_s
  end

  def determine_cmake_library_path
    sdk = MacOS.sdk_path if MacOS::Xcode.without_clt?
    paths = []
    # things expect to find GL headers since X11 used to be a default, so we add them
    paths << "#{sdk}/System/Library/Frameworks/OpenGL.framework/Versions/Current/Libraries" unless x11?
    paths << MacOS::X11.lib if x11?
    paths.to_path_s
  end

  def determine_aclocal_path
    paths = keg_only_deps.map{|dep| "#{HOMEBREW_PREFIX}/opt/#{dep}/share/aclocal" }
    paths << "#{HOMEBREW_PREFIX}/share/aclocal"
    paths << "#{MacOS::X11.share}/aclocal" if x11?
    paths.to_path_s
  end

  def determine_make_jobs
    if (j = self['HOMEBREW_MAKE_JOBS'].to_i) < 1
      Hardware::CPU.cores
    else
      j
    end
  end

  def determine_cccfg
    s = ""
    if ARGV.build_bottle?
      s << if ARGV.bottle_arch
        'bc'
      elsif Hardware::CPU.type == :intel
        if Hardware::CPU.is_64_bit?
          'bi6'
        else
          'bi'
        end
      elsif Hardware::CPU.type == :ppc
        if Hardware::CPU.altivec?
          'bpA'
        else
          'bp'
        end
      else
        'b'
      end
    end
    # Fix issue with sed barfing on unicode characters on Mountain Lion
    s << 's' if MacOS.version >= :mountain_lion
    # Fix issue with >= 10.8 apr-1-config having broken paths
    s << 'a' if MacOS.version >= :mountain_lion
    s
  end

  def determine_developer_dir
    # If Xcode path is fucked then this is basically a fix. In the case where
    # nothing is valid, it still fixes most usage to supply a valid path that
    # is not "/".
    MacOS::Xcode.prefix || self['DEVELOPER_DIR']
  end

  public

### NO LONGER NECESSARY OR NO LONGER SUPPORTED
  def noop(*args); end
  %w[m64 gcc_4_0_1 fast O4 O3 O2 Os Og O1 libxml2 minimal_optimization
    no_optimization enable_warnings x11
    set_cpu_flags
    macosxsdk remove_macosxsdk].each{|s| alias_method s, :noop }

### DEPRECATE THESE
  def deparallelize
    delete('MAKEFLAGS')
  end
  alias_method :j1, :deparallelize
  def gcc
    self['HOMEBREW_CC'] = "gcc-4.2"
    @compiler = :gcc
  end
  def gcc_4_0
    self['HOMEBREW_CC'] = "gcc-4.0"
    @compiler = :gcc_4_0
  end
  def llvm
    self['HOMEBREW_CC'] = "llvm-gcc"
    @compiler = :llvm
  end
  def clang
    self['HOMEBREW_CC'] = "clang"
    @compiler = :clang
  end
  GNU_GCC_VERSIONS.each do |n|
    define_method(:"gcc-4.#{n}") do
      @compiler = self['HOMEBREW_CC'] = "gcc-4.#{n}"
    end
  end
  def make_jobs
    self['MAKEFLAGS'] =~ /-\w*j(\d)+/
    [$1.to_i, 1].max
  end
end


class Array
  def to_path_s
    map(&:to_s).uniq.select{|s| File.directory? s }.join(File::PATH_SEPARATOR).chuzzle
  end
end
