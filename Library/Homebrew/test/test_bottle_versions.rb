require 'testing_env'
require 'bottle_version'

class BottleVersionParsingTests < Homebrew::TestCase
  def assert_version_detected expected, path
    assert_equal expected, BottleVersion.parse(path).to_s
  end

  def test_perforce_style
    assert_version_detected '2013.1.610569-x86_64',
      '/usr/local/perforce-2013.1.610569-x86_64.mountain_lion.bottle.tar.gz'
  end

  def test_ssh_copy_id_style
    assert_version_detected '6.2p2',
      '/usr/local/ssh-copy-id-6.2p2.mountain_lion.bottle.tar.gz'
  end

  def test_icu4c_style
    assert_version_detected '52.1',
      '/usr/local/icu4c-52.1.mavericks.bottle.tar.gz'
  end

  def test_x264_style
    assert_version_detected 'r2197.4',
      '/usr/local/x264-r2197.4.mavericks.bottle.tar.gz'
  end

  def test_lz4_style
    assert_version_detected 'r114',
      '/usr/local/lz4-r114.mavericks.bottle.tar.gz'
  end

  def test_pazpar2_style
    assert_version_detected '1.6.39',
      '/usr/local/pazpar2-1.6.39.mavericks.bottle.tar.gz'
  end

  def test_disco_style
    assert_version_detected '0_5_0',
      '/usr/local/disco-0_5_0.mavericks.bottle.tar.gz'
  end

  def test_zpython_style
    assert_version_detected '00-5.0.5',
      '/usr/local/zpython-00-5.0.5.mavericks.bottle.tar.gz'
  end

  def test_fontforge_style
    assert_version_detected '20120731',
      '/usr/local/fontforge-20120731.mavericks.bottle.tar.gz'
  end

  def test_erlang_style
    assert_version_detected 'R16B03-1',
      'erlang-R16B03-1.mavericks.bottle.2.tar.gz'
  end

  def test_erlang_versions_style
    assert_version_detected 'R14B04',
      'erlang-r14-R14B04.yosemite.bottle.tar.gz'
  end

  def test_libpano_style
    assert_version_detected '13-2.9.19',
      'libpano-13-2.9.19_1.yosemite.bottle.tar.gz'
  end

  def test_imapuw_style
    assert_version_detected '2007f',
      'imap-uw-2007f.yosemite.bottle.tar.gz'
  end

  def test_ngircd_style
    assert_version_detected '22',
      'ngircd-22.mavericks.bottle.tar.gz'
  end

  def test_apparix_style
    assert_version_detected '11-062',
      'apparix-11-062.yosemite.bottle.tar.gz'
  end

  def test_gcc_versions_style
    assert_version_detected '5-20150215',
      'gcc5-5-20150215.yosemite.bottle.tar.gz'
  end
end
