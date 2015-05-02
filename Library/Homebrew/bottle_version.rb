class BottleVersion < Version
  def self._parse spec
    spec = Pathname.new(spec) unless spec.is_a? Pathname
    stem = spec.stem

    # e.g. 5-20150215 from gcc5-5-20150215.yosemite.bottle.tar.gz
    m = /[a-z]{3}\d-(\d{1}-\d{8})/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. 1.0.2a-1 from openssl-1.0.2a-1.yosemite.bottle.1.tar.gz
    m = /-(\d+\.\d+(\.\d+)+[a-z]-\d+)/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. perforce-2013.1.610569-x86_64.mountain_lion.bottle.tar.gz
    m = /-([\d\.]+-x86(_64)?)/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. R14B04 from erlang-r14-R14B04.yosemite.bottle.tar.gz
    m = /erlang-r\d+-(R\d+B\d+(-\d)?)/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. x264-r2197.4.mavericks.bottle.tar.gz
    # e.g. lz4-r114.mavericks.bottle.tar.gz
    m = /-(r\d+\.?\d*)/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. 00-5.0.5 from zpython-00-5.0.5.mavericks.bottle.tar.gz
    # but not 00-2.0.0 from avce00-2.0.0.yosemite.bottle.tar.gz
    m = /-(00-\d+\.\d+(\.\d+)+)/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. 13-2.9.19 from libpano-13-2.9.19_1.yosemite.bottle.tar.gz
    # e.g. 11-062 from apparix-11-062.yosemite.bottle.tar.gz
    # but not 11-062.. from apparix-11-062..bottle.tar.gz
    m = /\D+-(\d+-\d+(\.\d+)*)/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. 1.6.39 from pazpar2-1.6.39.mavericks.bottle.tar.gz
    m = /-(\d+\.\d+(\.\d+)+)/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. ssh-copy-id-6.2p2.mountain_lion.bottle.tar.gz
    # e.g. icu4c-52.1.mountain_lion.bottle.tar.gz
    m = /-(\d+\.(\d)+(p(\d)+)?)/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. 20120731 from fontforge-20120731.mavericks.bottle.tar.gz
    m = /-(\d{8})/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. 2007f from imap-uw-2007f.yosemite.bottle.tar.gz
    m = /-(\d+[a-z])/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. 22 from ngircd-22.mavericks.bottle.tar.gz
    m = /-(\d{2})/.match(stem)
    return m.captures.first unless m.nil?

    # e.g. p17 from psutils-p17.yosemite.bottle.tar.gz
    m = /-(p\d{2})/.match(stem)
    return m.captures.first unless m.nil?

    super
  end
end
