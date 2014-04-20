module OS
  module Mac
    module Xcode
      extend self

      V4_BUNDLE_ID = "com.apple.dt.Xcode"
      V3_BUNDLE_ID = "com.apple.Xcode"
      V4_BUNDLE_PATH = Pathname.new("/Applications/Xcode.app")

      # Locate the "current Xcode folder" via xcode-select. See:
      # man xcode-select
      # TODO Should this be moved to OS::Mac? As of 10.9 this is referred to
      # as the "developer directory", and be either a CLT or Xcode instance.
      def folder
        @folder ||= `xcode-select -print-path 2>/dev/null`.strip
      end

      def latest_version
        case MacOS.version
        when "10.4"         then "2.5"
        when "10.5"         then "3.1.4"
        when "10.6"         then "3.2.6"
        when "10.7"         then "4.6.3"
        when "10.8"         then "5.1"
        when "10.9"         then "5.1"
        else
          # Default to newest known version of Xcode for unreleased OSX versions.
          if MacOS.version > "10.9"
            "5.1"
          else
            raise "Mac OS X '#{MacOS.version}' is invalid"
          end
        end
      end

      def outdated?
        version < latest_version
      end

      def without_clt?
        installed? && version >= "4.3" && !MacOS::CLT.installed?
      end

      def prefix
        @prefix ||= begin
          path = Pathname.new(folder)
          if path != CLT::MAVERICKS_PKG_PATH and path.absolute? \
             and File.executable? "#{path}/usr/bin/make"
            path
          elsif File.executable? '/Developer/usr/bin/make'
            # we do this to support cowboys who insist on installing
            # only a subset of Xcode
            Pathname.new('/Developer')
          # TODO remove this branch when 10.10 is released
          elsif File.executable? "#{V4_BUNDLE_PATH}/Contents/Developer/usr/bin/make"
            # TODO Remove this branch when 10.10 is released
            # This is a fallback for broken installations of Xcode 4.3+. Correct
            # installations will be handled by the first branch. Pretending that
            # broken installations are OK just leads to hard to diagnose problems
            # later.
            Pathname.new("#{V4_BUNDLE_PATH}/Contents/Developer")
          elsif (path = bundle_path)
            path += "Contents/Developer"
            path if File.executable? "#{path}/usr/bin/make"
          end
        end
      end

      # Ask Spotlight where Xcode is. If the user didn't install the
      # helper tools and installed Xcode in a non-conventional place, this
      # is our only option. See: http://superuser.com/questions/390757
      def bundle_path
        MacOS.app_with_bundle_id(V4_BUNDLE_ID, V3_BUNDLE_ID)
      end

      def installed?
        not prefix.nil?
      end

      def version
        # may return a version string
        # that is guessed based on the compiler, so do not
        # use it in order to check if Xcode is installed.
        @version ||= uncached_version
      end

      def uncached_version
        # This is a separate function as you can't cache the value out of a block
        # if return is used in the middle, which we do many times in here.

        return "0" unless OS.mac?

        %W[#{prefix}/usr/bin/xcodebuild #{which("xcodebuild")}].uniq.each do |path|
          if File.file? path
            `#{path} -version 2>/dev/null` =~ /Xcode (\d(\.\d)*)/
            return $1 if $1

            # Xcode 2.x's xcodebuild has a different version string
            `#{path} -version 2>/dev/null` =~ /DevToolsCore-(\d+\.\d)/
            case $1
            when "515.0" then return "2.0"
            when "798.0" then return "2.5"
            end
          end
        end

        # The remaining logic provides a fake Xcode version for CLT-only
        # systems. This behavior only exists because Homebrew used to assume
        # Xcode.version would always be non-nil. This is deprecated, and will
        # be removed in a future version. To remain compatible, guard usage of
        # Xcode.version with an Xcode.installed? check.
        case MacOS.llvm_build_version.to_i
        when 1..2063 then "3.1.0"
        when 2064..2065 then "3.1.4"
        when 2366..2325
          # we have no data for this range so we are guessing
          "3.2.0"
        when 2326
          # also applies to "3.2.3"
          "3.2.4"
        when 2327..2333 then "3.2.5"
        when 2335
          # this build number applies to 3.2.6, 4.0 and 4.1
          # https://github.com/Homebrew/homebrew/wiki/Xcode
          "4.0"
        else
          case (MacOS.clang_version.to_f * 10).to_i
          when 0       then "dunno"
          when 1..14   then "3.2.2"
          when 15      then "3.2.4"
          when 16      then "3.2.5"
          when 17..20  then "4.0"
          when 21      then "4.1"
          when 22..30  then "4.2"
          when 31      then "4.3"
          when 40      then "4.4"
          when 41      then "4.5"
          when 42      then "4.6"
          when 50      then "5.0"
          when 51      then "5.1"
          else "5.1"
          end
        end
      end

      def provides_autotools?
        # Xcode 2.5's autotools are too old to rely on at this point
        (version < "4.3") && (version > "2.5")
      end

      def provides_gcc?
        version < "4.3"
      end

      def provides_cvs?
        version < "5.0"
      end

      def default_prefix?
        if version < "4.3"
          %r{^/Developer} === prefix
        else
          %r{^/Applications/Xcode.app} === prefix
        end
      end
    end

    module CLT
      extend self

      STANDALONE_PKG_ID = "com.apple.pkg.DeveloperToolsCLILeo"
      FROM_XCODE_PKG_ID = "com.apple.pkg.DeveloperToolsCLI"
      MAVERICKS_PKG_ID = "com.apple.pkg.CLTools_Executables"
      MAVERICKS_PKG_PATH = Pathname.new("/Library/Developer/CommandLineTools")

      # Returns true even if outdated tools are installed, e.g.
      # tools from Xcode 4.x on 10.9
      def installed?
        !!detect_version
      end

      def latest_version
        if MacOS.version >= "10.8"
          "503.0.38"
        else
          "425.0.28"
        end
      end

      def outdated?
        version = `/usr/bin/clang --version`[%r{clang-(\d+\.\d+\.\d+)}, 1]
        return true unless version
        version < latest_version
      end

      # Version string (a pretty long one) of the CLT package.
      # Note, that different ways to install the CLTs lead to different
      # version numbers.
      def version
        @version ||= detect_version
      end

      def detect_version
        [MAVERICKS_PKG_ID, STANDALONE_PKG_ID, FROM_XCODE_PKG_ID].find do |id|
          version = MacOS.pkgutil_info(id)[/version: (.+)$/, 1]
          return version if version
        end
      end
    end
  end
end
