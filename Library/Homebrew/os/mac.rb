require 'hardware'
require 'os/mac/version'
require 'os/mac/xcode'
require 'os/mac/xquartz'

module OS
  module Mac
    extend self

    ::MacOS = self # compatibility

    # This can be compared to numerics, strings, or symbols
    # using the standard Ruby Comparable methods.
    def version
      @version ||= Version.new(MACOS_VERSION)
    end

    def cat
      version.to_sym
    end

    def locate tool
      # Don't call tools (cc, make, strip, etc.) directly!
      # Give the name of the binary you look for as a string to this method
      # in order to get the full path back as a Pathname.
      (@locate ||= {}).fetch(tool) do |key|
        @locate[key] = if File.executable?(path = "/usr/bin/#{tool}")
          Pathname.new path
        # Homebrew GCCs most frequently; much faster to check this before xcrun
        elsif File.executable?(path = "#{HOMEBREW_PREFIX}/bin/#{tool}")
          Pathname.new path
        else
          path = `/usr/bin/xcrun -no-cache -find #{tool} 2>/dev/null`.chomp
          Pathname.new(path) if File.executable?(path)
        end
      end
    end

    def active_developer_dir
      # xcode-select was introduced in Xcode 3 on Leopard
      return "/Developer" if MacOS.version < :leopard

      @active_developer_dir ||= `xcode-select -print-path 2>/dev/null`.strip
    end

    def sdk_path(v = version)
      (@sdk_path ||= {}).fetch(v.to_s) do |key|
        opts = []
        # First query Xcode itself
        opts << `#{locate('xcodebuild')} -version -sdk macosx#{v} Path 2>/dev/null`.chomp
        # Xcode.prefix is pretty smart, so lets look inside to find the sdk
        opts << "#{Xcode.prefix}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX#{v}.sdk"
        # Xcode < 4.3 style
        opts << "/Developer/SDKs/MacOSX#{v}.sdk"
        @sdk_path[key] = opts.map { |a| Pathname.new(a) }.detect(&:directory?)
      end
    end

    def default_cc
      cc = locate 'cc'
      cc.realpath.basename.to_s rescue nil
    end

    def default_compiler
      case default_cc
        # if GCC 4.2 is installed, e.g. via Tigerbrew, prefer it
        # over the system's GCC 4.0
        when /^gcc-4.0/ then gcc_42_build_version ? :gcc : :gcc_4_0
        when /^gcc/ then :gcc
        when /^llvm/ then :llvm
        when "clang" then :clang
        else
          # guess :(
          if Xcode.version >= "4.3"
            :clang
          elsif Xcode.version >= "4.2"
            :llvm
          else
            :gcc
          end
      end
    end

    def default_cxx_stdlib
      version >= :mavericks ? :libcxx : :libstdcxx
    end

    def gcc_40_build_version
      @gcc_40_build_version ||=
        if (path = locate("gcc-4.0"))
          %x{#{path} --version}[/build (\d{4,})/, 1].to_i
        end
    end
    alias_method :gcc_4_0_build_version, :gcc_40_build_version

    def gcc_42_build_version
      @gcc_42_build_version ||=
        begin
          gcc = MacOS.locate("gcc-4.2") || HOMEBREW_PREFIX.join("opt/apple-gcc42/bin/gcc-4.2")
          if gcc.exist? && gcc.realpath.basename.to_s !~ /^llvm/
            %x{#{gcc} --version}[/build (\d{4,})/, 1].to_i
          end
        end
    end
    alias_method :gcc_build_version, :gcc_42_build_version

    def llvm_build_version
      @llvm_build_version ||=
        if (path = locate("llvm-gcc")) && path.realpath.basename.to_s !~ /^clang/
          %x{#{path} --version}[/LLVM build (\d{4,})/, 1].to_i
        end
    end

    def clang_version
      @clang_version ||=
        if (path = locate("clang"))
          %x{#{path} --version}[/(?:clang|LLVM) version (\d\.\d)/, 1]
        end
    end

    def clang_build_version
      @clang_build_version ||=
        if (path = locate("clang"))
          %x{#{path} --version}[%r[clang-(\d{2,})], 1].to_i
        end
    end

    def non_apple_gcc_version(cc)
      path = HOMEBREW_PREFIX.join("opt/gcc/bin/#{cc}")
      path = nil unless path.exist?

      return unless path ||= locate(cc)

      ivar = "@#{cc.gsub(/(-|\.)/, '')}_version"
      return instance_variable_get(ivar) if instance_variable_defined?(ivar)

      `#{path} --version` =~ /gcc(-\d\.\d \(.+\))? (\d\.\d\.\d)/
      instance_variable_set(ivar, $2)
    end

    # See these issues for some history:
    # http://github.com/Homebrew/homebrew/issues/13
    # http://github.com/Homebrew/homebrew/issues/41
    # http://github.com/Homebrew/homebrew/issues/48
    def macports_or_fink
      paths = []

      # First look in the path because MacPorts is relocatable and Fink
      # may become relocatable in the future.
      %w{port fink}.each do |ponk|
        path = which(ponk)
        paths << path unless path.nil?
      end

      # Look in the standard locations, because even if port or fink are
      # not in the path they can still break builds if the build scripts
      # have these paths baked in.
      %w{/sw/bin/fink /opt/local/bin/port}.each do |ponk|
        path = Pathname.new(ponk)
        paths << path if path.exist?
      end

      # Finally, some users make their MacPorts or Fink directorie
      # read-only in order to try out Homebrew, but this doens't work as
      # some build scripts error out when trying to read from these now
      # unreadable paths.
      %w{/sw /opt/local}.map { |p| Pathname.new(p) }.each do |path|
        paths << path if path.exist? && !path.readable?
      end

      paths.uniq
    end

    def prefer_64_bit?
      if ENV['HOMEBREW_PREFER_64_BIT'] && MacOS.version == :leopard
        Hardware::CPU.is_64_bit?
      else
        Hardware::CPU.is_64_bit? and version > :leopard
      end
    end

    def preferred_arch
      if prefer_64_bit?
        Hardware::CPU.arch_64_bit
      else
        Hardware::CPU.arch_32_bit
      end
    end

    STANDARD_COMPILERS = {
      "2.0"   => { :gcc_40_build => 4061 },
      "2.5"   => { :gcc_40_build => 5370 },
      "3.1.4" => { :gcc_40_build => 5493, :gcc_42_build => 5577 },
      "3.2.6" => { :gcc_40_build => 5494, :gcc_42_build => 5666, :llvm_build => 2335, :clang => "1.7", :clang_build => 77 },
      "4.0"   => { :gcc_40_build => 5494, :gcc_42_build => 5666, :llvm_build => 2335, :clang => "2.0", :clang_build => 137 },
      "4.0.1" => { :gcc_40_build => 5494, :gcc_42_build => 5666, :llvm_build => 2335, :clang => "2.0", :clang_build => 137 },
      "4.0.2" => { :gcc_40_build => 5494, :gcc_42_build => 5666, :llvm_build => 2335, :clang => "2.0", :clang_build => 137 },
      "4.2"   => { :llvm_build => 2336, :clang => "3.0", :clang_build => 211 },
      "4.3"   => { :llvm_build => 2336, :clang => "3.1", :clang_build => 318 },
      "4.3.1" => { :llvm_build => 2336, :clang => "3.1", :clang_build => 318 },
      "4.3.2" => { :llvm_build => 2336, :clang => "3.1", :clang_build => 318 },
      "4.3.3" => { :llvm_build => 2336, :clang => "3.1", :clang_build => 318 },
      "4.4"   => { :llvm_build => 2336, :clang => "4.0", :clang_build => 421 },
      "4.4.1" => { :llvm_build => 2336, :clang => "4.0", :clang_build => 421 },
      "4.5"   => { :llvm_build => 2336, :clang => "4.1", :clang_build => 421 },
      "4.5.1" => { :llvm_build => 2336, :clang => "4.1", :clang_build => 421 },
      "4.5.2" => { :llvm_build => 2336, :clang => "4.1", :clang_build => 421 },
      "4.6"   => { :llvm_build => 2336, :clang => "4.2", :clang_build => 425 },
      "4.6.1" => { :llvm_build => 2336, :clang => "4.2", :clang_build => 425 },
      "4.6.2" => { :llvm_build => 2336, :clang => "4.2", :clang_build => 425 },
      "4.6.3" => { :llvm_build => 2336, :clang => "4.2", :clang_build => 425 },
      "5.0"   => { :clang => "5.0", :clang_build => 500 },
      "5.0.1" => { :clang => "5.0", :clang_build => 500 },
      "5.0.2" => { :clang => "5.0", :clang_build => 500 },
      "5.1"   => { :clang => "5.1", :clang_build => 503 },
      "5.1.1" => { :clang => "5.1", :clang_build => 503 },
    }

    def compilers_standard?
      STANDARD_COMPILERS.fetch(Xcode.version.to_s).all? do |method, build|
        send(:"#{method}_version") == build
      end
    rescue IndexError
      onoe <<-EOS.undent
        Homebrew doesn't know what compiler versions ship with your version
        of Xcode (#{Xcode.version}). Please `brew update` and if that doesn't help, file
        an issue with the output of `brew --config`:
          https://github.com/Homebrew/homebrew/issues

        Note that we only track stable, released versions of Xcode.

        Thanks!
      EOS
    end

    def app_with_bundle_id(*ids)
      path = mdfind(*ids).first
      Pathname.new(path) unless path.nil? or path.empty?
    end

    def mdfind(*ids)
      return [] unless OS.mac?
      (@mdfind ||= {}).fetch(ids) do
        @mdfind[ids] = `/usr/bin/mdfind "#{mdfind_query(*ids)}"`.split("\n")
      end
    end

    def pkgutil_info(id)
      (@pkginfo ||= {}).fetch(id) do |key|
        @pkginfo[key] = `/usr/sbin/pkgutil --pkg-info "#{key}" 2>/dev/null`.strip
      end
    end

    def mdfind_query(*ids)
      ids.map! { |id| "kMDItemCFBundleIdentifier == #{id}" }.join(" || ")
    end
  end
end
