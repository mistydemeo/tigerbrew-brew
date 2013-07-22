module MacOS::XQuartz extend self
  FORGE_BUNDLE_ID = "org.macosforge.xquartz.X11"
  APPLE_BUNDLE_ID = "org.x.X11"
  FORGE_PKG_ID = "org.macosforge.xquartz.pkg"

  PKGINFO_VERSION_MAP = {
    "2.6.34" => "2.6.3",
    "2.7.4"  => "2.7.0",
    "2.7.14" => "2.7.1",
    "2.7.28" => "2.7.2",
    "2.7.32" => "2.7.3",
    "2.7.43" => "2.7.4",
    "2.7.50" => "2.7.5_rc1",
    "2.7.51" => "2.7.5_rc2",
  }.freeze

  # This returns the version number of XQuartz, not of the upstream X.org.
  # The X11.app distributed by Apple is also XQuartz, and therefore covered
  # by this method.
  def version
    @version ||= detect_version
  end

  def detect_version
    if (path = bundle_path) && path.exist? && (version = version_from_mdls(path))
      version
    elsif prefix.to_s == "/usr/X11" || prefix.to_s == "/usr/X11R6"
      guess_system_version
    else
      version_from_pkgutil
    end
  end

  def latest_version
    # XQuartz only supports 10.6 and newer
    if MacOS.version == :leopard
      "2.1.6"
    else
      "2.7.4"
    end
  end

  def bundle_path
    MacOS.app_with_bundle_id(FORGE_BUNDLE_ID) || MacOS.app_with_bundle_id(APPLE_BUNDLE_ID)
  end

  def version_from_mdls(path)
    version = `mdls -raw -nullMarker "" -name kMDItemVersion "#{path}" 2>/dev/null`.strip
    version unless version.empty?
  end

  # The XQuartz that Apple shipped in OS X through 10.7 does not have a
  # pkg-util entry, so if Spotlight indexing is disabled we must make an
  # educated guess as to what version is installed.
  def guess_system_version
    case MacOS.version
    when '10.4' then '1.1.3'
    when '10.5' then '2.1.6'
    when '10.6' then '2.3.6'
    when '10.7' then '2.6.3'
    else 'dunno'
    end
  end

  # Upstream XQuartz *does* have a pkg-info entry, so if we can't get it
  # from mdls, we can try pkgutil. This is very slow.
  def version_from_pkgutil
    str = MacOS.pkgutil_info(FORGE_PKG_ID)[/version: (\d\.\d\.\d+)$/, 1]
    PKGINFO_VERSION_MAP.fetch(str, str)
  end

  def provided_by_apple?
    # Tiger X11 has no bundle id, but this old directory is only from Apple
    return true if prefix.to_s == "/usr/X11R6"

    [FORGE_BUNDLE_ID, APPLE_BUNDLE_ID].find do |id|
      MacOS.app_with_bundle_id(id)
    end == APPLE_BUNDLE_ID
  end

  # This should really be private, but for compatibility reasons it must
  # remain public. New code should use MacOS::X11.{bin,lib,include}
  # instead, as that accounts for Xcode-only systems.
  def prefix
    @prefix ||= if Pathname.new('/opt/X11/lib/libpng.dylib').exist?
      Pathname.new('/opt/X11')
    elsif Pathname.new('/usr/X11/lib/libpng.dylib').exist?
      Pathname.new('/usr/X11')
    # X11 doesn't include libpng on Tiger
    elsif File.exist?('/usr/X11R6/lib/libX11.dylib')
      Pathname.new('/usr/X11R6')
    end
  end

  def installed?
    !version.nil? && !prefix.nil?
  end
end

module MacOS::X11 extend self
  def prefix
    MacOS::XQuartz.prefix
  end

  def installed?
    MacOS::XQuartz.installed?
  end

  # If XQuartz and/or the CLT are installed, headers will be found under
  # /opt/X11/include or /usr/X11/include. For Xcode-only systems, they are
  # found in the SDK, so we use sdk_path for both the headers and libraries.
  # Confusingly, executables (e.g. config scripts) are only found under
  # /opt/X11/bin or /usr/X11/bin in all cases.
  def bin
    Pathname.new("#{prefix}/bin")
  end

  def include
    @include ||= if use_sdk?
      Pathname.new("#{MacOS.sdk_path}/usr/X11/include")
    else
      Pathname.new("#{prefix}/include")
    end
  end

  def lib
    @lib ||= if use_sdk?
      Pathname.new("#{MacOS.sdk_path}/usr/X11/lib")
    else
      Pathname.new("#{prefix}/lib")
    end
  end

  def share
    Pathname.new("#{prefix}/share")
  end

  private

  def use_sdk?
    not (prefix.to_s == '/opt/X11' or MacOS::CLT.installed?)
  end
end
