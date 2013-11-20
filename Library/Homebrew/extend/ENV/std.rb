# -*- coding: utf-8 -*-
require 'hardware'
require 'os/mac'
require 'extend/ENV/shared'

module Stdenv
  include SharedEnvExtension

  SAFE_CFLAGS_FLAGS = "-w -pipe"
  DEFAULT_FLAGS = '-march=core2 -msse4'

  def self.extended(base)
    unless ORIGINAL_PATHS.include? HOMEBREW_PREFIX/'bin'
      base.prepend_path 'PATH', "#{HOMEBREW_PREFIX}/bin"
    end
  end

  def setup_build_environment(formula=nil)
    # Clear CDPATH to avoid make issues that depend on changing directories
    delete('CDPATH')
    delete('GREP_OPTIONS') # can break CMake (lol)
    delete('CLICOLOR_FORCE') # autotools doesn't like this
    %w{CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH}.each { |k| delete(k) }
    remove_cc_etc

    if MacOS.version >= :mountain_lion
      # Mountain Lion's sed is stricter, and errors out when
      # it encounters files with mixed character sets
      delete('LC_ALL')
      self['LC_CTYPE']="C"
    end

    # Set the default pkg-config search path, overriding the built-in paths
    # Anything in PKG_CONFIG_PATH is searched before paths in this variable
    self['PKG_CONFIG_LIBDIR'] = determine_pkg_config_libdir

    # make any aclocal stuff installed in Homebrew available
    self['ACLOCAL_PATH'] = "#{HOMEBREW_PREFIX}/share/aclocal" if MacOS::Xcode.provides_autotools?

    self['MAKEFLAGS'] = "-j#{self.make_jobs}"

    unless HOMEBREW_PREFIX.to_s == '/usr/local'
      # /usr/local is already an -isystem and -L directory so we skip it
      self['CPPFLAGS'] = "-isystem#{HOMEBREW_PREFIX}/include"
      self['LDFLAGS'] = "-L#{HOMEBREW_PREFIX}/lib"
      # CMake ignores the variables above
      self['CMAKE_PREFIX_PATH'] = "#{HOMEBREW_PREFIX}"
    end

    if (HOMEBREW_PREFIX/'Frameworks').exist?
      append 'CPPFLAGS', "-F#{HOMEBREW_PREFIX}/Frameworks"
      append 'LDFLAGS', "-F#{HOMEBREW_PREFIX}/Frameworks"
      self['CMAKE_FRAMEWORK_PATH'] = HOMEBREW_PREFIX/"Frameworks"
    end

    # Os is the default Apple uses for all its stuff so let's trust them
    set_cflags "-Os #{SAFE_CFLAGS_FLAGS}"

    append 'LDFLAGS', '-Wl,-headerpad_max_install_names'

    # set us up for the user's compiler choice
    self.send self.compiler

    # we must have a working compiler!
    unless cc
      @compiler = MacOS.default_compiler
      self.send @compiler
      self.cc  = MacOS.locate("cc")
      self.cxx = MacOS.locate("c++")
    end

    validate_cc!(formula) unless formula.nil?

    if cc =~ GNU_GCC_REGEXP
      warn_about_non_apple_gcc($1)
      gcc_name = 'gcc' + $1.delete('.')
      gcc = Formulary.factory(gcc_name)
      self.append_path('PATH', gcc.opt_prefix/'bin')
    end

    # Add lib and include etc. from the current macosxsdk to compiler flags:
    macosxsdk MacOS.version

    if MacOS::Xcode.without_clt?
      # Some tools (clang, etc.) are in the xctoolchain dir of Xcode
      append_path 'PATH', "#{MacOS.xctoolchain_path}/usr/bin" if MacOS.xctoolchain_path
      # Others are now at /Applications/Xcode.app/Contents/Developer/usr/bin
      append_path 'PATH', MacOS.dev_tools_path
    end

    # Leopard's ld needs some convincing that it's building 64-bit
    # See: https://github.com/mistydemeo/tigerbrew/issues/59
    if MacOS.version == :leopard && MacOS.prefer_64_bit?
      append 'LDFLAGS', "-arch #{Hardware::CPU.arch_64_bit}"

      # Many, many builds are broken thanks to Leopard's buggy ld.
      # Our ld64 fixes many of those builds, though of course we can't
      # depend on it already being installed to build itself.
      ld64 if Formula.factory('ld64').installed?
    end
  end

  def determine_pkg_config_libdir
    paths = []
    paths << HOMEBREW_PREFIX/'lib/pkgconfig'
    paths << HOMEBREW_PREFIX/'share/pkgconfig'
    paths << HOMEBREW_REPOSITORY/"Library/ENV/pkgconfig/#{MacOS.version}"
    paths << '/usr/lib/pkgconfig'
    paths.select { |d| File.directory? d }.join(File::PATH_SEPARATOR)
  end

  def deparallelize
    remove 'MAKEFLAGS', /-j\d+/
  end
  alias_method :j1, :deparallelize

  # These methods are no-ops for compatibility.
  %w{fast Og}.each { |opt| define_method(opt) {} }

  %w{O4 O3 O2 O1 O0 Os}.each do |opt|
    define_method opt do
      remove_from_cflags(/-O./)
      append_to_cflags "-#{opt}"
    end
  end

  def gcc_4_0_1
    # we don't use locate because gcc 4.0 has not been provided since Xcode 4
    self.cc  = "#{MacOS.dev_tools_path}/gcc-4.0"
    self.cxx = "#{MacOS.dev_tools_path}/g++-4.0"
    replace_in_cflags '-O4', '-O3'
    set_cpu_cflags '-march=nocona -mssse3'
    @compiler = :gcc
  end
  alias_method :gcc_4_0, :gcc_4_0_1

  def gcc
    # Apple stopped shipping gcc-4.2 with Xcode 4.2
    # However they still provide a gcc symlink to llvm
    # But we don't want LLVM of course.

    self.cc  = MacOS.locate("gcc-4.2")
    self.cxx = MacOS.locate("g++-4.2")

    unless cc
      self.cc  = "#{HOMEBREW_PREFIX}/bin/gcc-4.2"
      self.cxx = "#{HOMEBREW_PREFIX}/bin/g++-4.2"
      raise "GCC could not be found" unless File.exist? cc
    end

    unless cc =~ %r{^/usr/bin/xcrun }
      raise "GCC could not be found" if Pathname.new(cc).realpath.to_s =~ /llvm/
    end

    replace_in_cflags '-O4', '-O3'
    set_cpu_cflags
    @compiler = :gcc
  end
  alias_method :gcc_4_2, :gcc

  GNU_GCC_VERSIONS.each do |n|
    define_method(:"gcc-4.#{n}") do
      gcc = "gcc-4.#{n}"
      self.cc = self['OBJC'] = gcc
      self.cxx = self['OBJCXX'] = gcc.gsub('c', '+')
      set_cpu_cflags
      @compiler = gcc
    end
  end

  def llvm
    self.cc  = MacOS.locate("llvm-gcc")
    self.cxx = MacOS.locate("llvm-g++")
    set_cpu_cflags
    @compiler = :llvm
  end

  def clang
    self.cc  = MacOS.locate("clang")
    self.cxx = MacOS.locate("clang++")
    replace_in_cflags(/-Xarch_#{Hardware::CPU.arch_32_bit} (-march=\S*)/, '\1')
    # Clang mistakenly enables AES-NI on plain Nehalem
    set_cpu_cflags '-march=native', :nehalem => '-march=native -Xclang -target-feature -Xclang -aes'
    @compiler = :clang
  end

  def remove_macosxsdk version=MacOS.version
    # Clear all lib and include dirs from CFLAGS, CPPFLAGS, LDFLAGS that were
    # previously added by macosxsdk
    version = version.to_s
    remove_from_cflags(/ ?-mmacosx-version-min=10\.\d/)
    delete('MACOSX_DEPLOYMENT_TARGET')
    delete('CPATH')
    remove 'LDFLAGS', "-L#{HOMEBREW_PREFIX}/lib"

    if (sdk = MacOS.sdk_path(version)) && !MacOS::CLT.installed?
      delete('SDKROOT')
      remove_from_cflags "-isysroot #{sdk}"
      remove 'CPPFLAGS', "-isysroot #{sdk}"
      remove 'LDFLAGS', "-isysroot #{sdk}"
      if HOMEBREW_PREFIX.to_s == '/usr/local'
        delete('CMAKE_PREFIX_PATH')
      else
        # It was set in setup_build_environment, so we have to restore it here.
        self['CMAKE_PREFIX_PATH'] = "#{HOMEBREW_PREFIX}"
      end
      remove 'CMAKE_FRAMEWORK_PATH', "#{sdk}/System/Library/Frameworks"
    end
  end

  def macosxsdk version=MacOS.version
    return unless OS.mac?
    # Sets all needed lib and include dirs to CFLAGS, CPPFLAGS, LDFLAGS.
    remove_macosxsdk
    version = version.to_s
    append_to_cflags("-mmacosx-version-min=#{version}")
    self['MACOSX_DEPLOYMENT_TARGET'] = version
    self['CPATH'] = "#{HOMEBREW_PREFIX}/include"
    prepend 'LDFLAGS', "-L#{HOMEBREW_PREFIX}/lib"

    if (sdk = MacOS.sdk_path(version)) && !MacOS::CLT.installed?
      # Extra setup to support Xcode 4.3+ without CLT.
      self['SDKROOT'] = sdk
      # Tell clang/gcc where system include's are:
      append_path 'CPATH', "#{sdk}/usr/include"
      # The -isysroot is needed, too, because of the Frameworks
      append_to_cflags "-isysroot #{sdk}"
      append 'CPPFLAGS', "-isysroot #{sdk}"
      # And the linker needs to find sdk/usr/lib
      append 'LDFLAGS', "-isysroot #{sdk}"
      # Needed to build cmake itself and perhaps some cmake projects:
      append_path 'CMAKE_PREFIX_PATH', "#{sdk}/usr"
      append_path 'CMAKE_FRAMEWORK_PATH', "#{sdk}/System/Library/Frameworks"
    end
  end

  def minimal_optimization
    set_cflags "-Os #{SAFE_CFLAGS_FLAGS}"
    macosxsdk unless MacOS::CLT.installed?
  end
  def no_optimization
    set_cflags SAFE_CFLAGS_FLAGS
    macosxsdk unless MacOS::CLT.installed?
  end

  # Some configure scripts won't find libxml2 without help
  def libxml2
    if MacOS::CLT.installed?
      append 'CPPFLAGS', '-I/usr/include/libxml2'
    else
      # Use the includes form the sdk
      append 'CPPFLAGS', "-I#{MacOS.sdk_path}/usr/include/libxml2"
    end
  end

  def x11
    # There are some config scripts here that should go in the PATH
    append_path 'PATH', MacOS::X11.bin

    # Append these to PKG_CONFIG_LIBDIR so they are searched
    # *after* our own pkgconfig directories, as we dupe some of the
    # libs in XQuartz.
    append_path 'PKG_CONFIG_LIBDIR', MacOS::X11.lib/'pkgconfig'
    append_path 'PKG_CONFIG_LIBDIR', MacOS::X11.share/'pkgconfig'

    append 'LDFLAGS', "-L#{MacOS::X11.lib}"
    append_path 'CMAKE_PREFIX_PATH', MacOS::X11.prefix
    append_path 'CMAKE_INCLUDE_PATH', MacOS::X11.include
    append_path 'CMAKE_INCLUDE_PATH', MacOS::X11.include/'freetype2'

    append 'CPPFLAGS', "-I#{MacOS::X11.include}"
    append 'CPPFLAGS', "-I#{MacOS::X11.include}/freetype2"

    append_path 'ACLOCAL_PATH', MacOS::X11.share/'aclocal'

    if MacOS::XQuartz.provided_by_apple? and not MacOS::CLT.installed?
      append_path 'CMAKE_PREFIX_PATH', MacOS.sdk_path/'usr/X11'
    end

    append 'CFLAGS', "-I#{MacOS::X11.include}" unless MacOS::CLT.installed?
  end
  alias_method :libpng, :x11

  # we've seen some packages fail to build when warnings are disabled!
  def enable_warnings
    remove_from_cflags '-w'
    remove_from_cflags '-Qunused-arguments'
  end

  def m64
    append_to_cflags '-m64'
    append 'LDFLAGS', "-arch #{Hardware::CPU.arch_64_bit}"
  end
  def m32
    append_to_cflags '-m32'
    append 'LDFLAGS', "-arch #{Hardware::CPU.arch_32_bit}"
  end

  def universal_binary
    append_to_cflags Hardware::CPU.universal_archs.as_arch_flags
    replace_in_cflags '-O4', '-O3' # O4 seems to cause the build to fail
    append 'LDFLAGS', Hardware::CPU.universal_archs.as_arch_flags

    if compiler != :clang && Hardware.is_32_bit?
      # Can't mix "-march" for a 32-bit CPU  with "-arch x86_64"
      replace_in_cflags(/-march=\S*/, "-Xarch_#{Hardware::CPU.arch_32_bit} \\0")
    end
  end

  def cxx11
    if compiler == :clang
      append 'CXX', '-std=c++11'
      append 'CXX', '-stdlib=libc++'
    elsif compiler =~ /gcc-4\.(8|9)/
      append 'CXX', '-std=c++11'
    else
      raise "The selected compiler doesn't support C++11: #{compiler}"
    end
  end

  def libcxx
    if compiler == :clang
      append 'CXX', '-stdlib=libc++'
    end
  end

  def libstdcxx
    if compiler == :clang
      append 'CXX', '-stdlib=libstdc++'
    end
  end

  def replace_in_cflags before, after
    CC_FLAG_VARS.each do |key|
      self[key] = self[key].sub(before, after) if has_key?(key)
    end
  end

  # Convenience method to set all C compiler flags in one shot.
  def set_cflags val
    CC_FLAG_VARS.each { |key| self[key] = val }
  end

  # Sets architecture-specific flags for every environment variable
  # given in the list `flags`.
  def set_cpu_flags flags, default=DEFAULT_FLAGS, map=Hardware::CPU.optimization_flags
    cflags =~ %r{(-Xarch_#{Hardware::CPU.arch_32_bit} )-march=}
    xarch = $1.to_s
    remove flags, %r{(-Xarch_#{Hardware::CPU.arch_32_bit} )?-march=\S*}
    remove flags, %r{( -Xclang \S+)+}
    remove flags, %r{-mssse3}
    remove flags, %r{-msse4(\.\d)?}
    append flags, xarch unless xarch.empty?

    if ARGV.build_bottle?
      arch = ARGV.bottle_arch || Hardware.oldest_cpu
      append flags, Hardware::CPU.optimization_flags.fetch(arch)
    else
      # Don't set -msse3 and older flags because -march does that for us
      append flags, map.fetch(Hardware::CPU.family, default)
    end

    # Works around a buggy system header on Tiger
    append flags, "-faltivec" if MacOS.version == :tiger

    # not really a 'CPU' cflag, but is only used with clang
    remove flags, '-Qunused-arguments'
  end

  def set_cpu_cflags default=DEFAULT_FLAGS, map=Hardware::CPU.optimization_flags
    set_cpu_flags CC_FLAG_VARS, default, map
  end

  def make_jobs
    # '-j' requires a positive integral argument
    if self['HOMEBREW_MAKE_JOBS'].to_i > 0
      self['HOMEBREW_MAKE_JOBS'].to_i
    else
      Hardware::CPU.cores
    end
  end
end
