require 'testing_env'
require 'test/testball'

class AbstractDownloadStrategy
  attr_reader :url
end

class MostlyAbstractFormula < Formula
  url ''
end

class FormulaTests < Test::Unit::TestCase
  include VersionAssertions

  def test_prefix
    shutup do
      TestBall.new.brew do |f|
        assert_equal File.expand_path(f.prefix), (HOMEBREW_CELLAR+f.name+'0.1').to_s
        assert_kind_of Pathname, f.prefix
      end
    end
  end

  def test_class_naming
    assert_equal 'ShellFm', Formula.class_s('shell.fm')
    assert_equal 'Fooxx', Formula.class_s('foo++')
    assert_equal 'SLang', Formula.class_s('s-lang')
    assert_equal 'PkgConfig', Formula.class_s('pkg-config')
    assert_equal 'FooBar', Formula.class_s('foo_bar')
  end

  def test_cant_override_brew
    assert_raises(RuntimeError) do
      eval <<-EOS
      class TestBallOverrideBrew < Formula
        def initialize
          super "foo"
        end
        def brew
        end
      end
      EOS
    end
  end

  def test_abstract_formula
    f=MostlyAbstractFormula.new
    assert_equal '__UNKNOWN__', f.name
    assert_raises(RuntimeError) { f.prefix }
    shutup { assert_raises(RuntimeError) { f.brew } }
  end

  def test_mirror_support
    HOMEBREW_CACHE.mkpath unless HOMEBREW_CACHE.exist?
    shutup do
      f = TestBallWithMirror.new
      _, downloader = f.fetch
      assert_equal f.url, "file:///#{TEST_FOLDER}/bad_url/testball-0.1.tbz"
      assert_equal downloader.url, "file:///#{TEST_FOLDER}/tarballs/testball-0.1.tbz"
    end
  end

  def test_formula_specs
    f = SpecTestBall.new

    assert_equal 'http://example.com', f.homepage
    assert_equal 'file:///foo.com/testball-0.1.tbz', f.url
    assert_equal 1, f.mirrors.length
    assert_version_equal '0.1', f.version
    assert_equal f.stable, f.active_spec
    assert_equal CurlDownloadStrategy, f.download_strategy
    assert_instance_of CurlDownloadStrategy, f.downloader

    assert_instance_of SoftwareSpec, f.stable
    assert_instance_of Bottle, f.bottle
    assert_instance_of SoftwareSpec, f.devel
    assert_instance_of HeadSoftwareSpec, f.head

    assert_equal 'file:///foo.com/testball-0.1.tbz', f.stable.url
    assert_equal "https://downloads.sf.net/project/machomebrew/Bottles/spectestball-0.1.#{MacOS.cat}.bottle.tar.gz",
      f.bottle.url
    assert_equal 'file:///foo.com/testball-0.2.tbz', f.devel.url
    assert_equal 'https://github.com/mxcl/homebrew.git', f.head.url

    assert_empty f.stable.specs
    assert_empty f.bottle.specs
    assert_empty f.devel.specs
    assert_equal({ :tag => 'foo' }, f.head.specs)

    assert_equal CurlDownloadStrategy, f.stable.download_strategy
    assert_equal CurlBottleDownloadStrategy, f.bottle.download_strategy
    assert_equal CurlDownloadStrategy, f.devel.download_strategy
    assert_equal GitDownloadStrategy, f.head.download_strategy

    assert_instance_of Checksum, f.stable.checksum
    assert_instance_of Checksum, f.bottle.checksum
    assert_instance_of Checksum, f.devel.checksum
    assert !f.stable.checksum.empty?
    assert !f.bottle.checksum.empty?
    assert !f.devel.checksum.empty?
    assert_nil f.head.checksum
    assert_equal :sha1, f.stable.checksum.hash_type
    assert_equal :sha1, f.bottle.checksum.hash_type
    assert_equal :sha256, f.devel.checksum.hash_type
    assert_equal case MacOS.cat
      when :snow_leopard_32 then 'deadbeef'*5
      when :snow_leopard    then 'faceb00c'*5
      when :lion            then 'baadf00d'*5
      when :mountain_lion   then '8badf00d'*5
      end, f.bottle.checksum.hexdigest
    assert_match(/[0-9a-fA-F]{40}/, f.stable.checksum.hexdigest)
    assert_match(/[0-9a-fA-F]{64}/, f.devel.checksum.hexdigest)

    assert_equal 1, f.stable.mirrors.length
    assert f.bottle.mirrors.empty?
    assert_equal 1, f.devel.mirrors.length
    assert f.head.mirrors.empty?

    assert f.stable.version.detected_from_url?
    assert f.bottle.version.detected_from_url?
    assert f.devel.version.detected_from_url?
    assert_version_equal '0.1', f.stable.version
    assert_version_equal '0.1', f.bottle.version
    assert_version_equal '0.2', f.devel.version
    assert_version_equal 'HEAD', f.head.version
    assert_equal 0, f.bottle.revision
  end

  def test_devel_active_spec
    ARGV.push '--devel'
    f = SpecTestBall.new
    assert_equal f.devel, f.active_spec
    assert_version_equal '0.2', f.version
    assert_equal 'file:///foo.com/testball-0.2.tbz', f.url
    assert_equal CurlDownloadStrategy, f.download_strategy
    assert_instance_of CurlDownloadStrategy, f.downloader
    ARGV.delete '--devel'
  end

  def test_head_active_spec
    ARGV.push '--HEAD'
    f = SpecTestBall.new
    assert_equal f.head, f.active_spec
    assert_version_equal 'HEAD', f.version
    assert_equal 'https://github.com/mxcl/homebrew.git', f.url
    assert_equal GitDownloadStrategy, f.download_strategy
    assert_instance_of GitDownloadStrategy, f.downloader
    ARGV.delete '--HEAD'
  end

  def test_explicit_version_spec
    f = ExplicitVersionSpecTestBall.new
    assert_version_equal '0.3', f.version
    assert_version_equal '0.3', f.stable.version
    assert_version_equal '0.4', f.devel.version
    assert !f.stable.version.detected_from_url?
    assert !f.devel.version.detected_from_url?
  end

  def test_head_only_specs
    f = HeadOnlySpecTestBall.new

    assert_nil f.stable
    assert_nil f.bottle
    assert_nil f.devel

    assert_equal f.head, f.active_spec
    assert_version_equal 'HEAD', f.version
    assert_nil f.head.checksum
    assert_equal 'https://github.com/mxcl/homebrew.git', f.url
    assert_equal GitDownloadStrategy, f.download_strategy
    assert_instance_of GitDownloadStrategy, f.downloader
    assert_instance_of HeadSoftwareSpec, f.head
  end

  def test_incomplete_stable_specs
    f = IncompleteStableSpecTestBall.new

    assert_nil f.stable
    assert_nil f.bottle
    assert_nil f.devel

    assert_equal f.head, f.active_spec
    assert_version_equal 'HEAD', f.version
    assert_nil f.head.checksum
    assert_equal 'https://github.com/mxcl/homebrew.git', f.url
    assert_equal GitDownloadStrategy, f.download_strategy
    assert_instance_of GitDownloadStrategy, f.downloader
    assert_instance_of HeadSoftwareSpec, f.head
  end

  def test_head_only_with_version_specs
    f = IncompleteStableSpecTestBall.new

    assert_nil f.stable
    assert_nil f.bottle
    assert_nil f.devel

    assert_equal f.head, f.active_spec
    assert_version_equal 'HEAD', f.version
    assert_nil f.head.checksum
    assert_equal 'https://github.com/mxcl/homebrew.git', f.url
    assert_equal GitDownloadStrategy, f.download_strategy
    assert_instance_of GitDownloadStrategy, f.downloader
    assert_instance_of HeadSoftwareSpec, f.head
  end

  def test_explicit_strategy_specs
    f = ExplicitStrategySpecTestBall.new

    assert_instance_of SoftwareSpec, f.stable
    assert_instance_of SoftwareSpec, f.devel
    assert_instance_of HeadSoftwareSpec, f.head

    assert_equal f.stable, f.active_spec

    assert_nil f.stable.checksum
    assert_nil f.devel.checksum
    assert_nil f.head.checksum

    assert_equal MercurialDownloadStrategy, f.stable.download_strategy
    assert_equal BazaarDownloadStrategy, f.devel.download_strategy
    assert_equal SubversionDownloadStrategy, f.head.download_strategy

    assert_equal({ :tag => '0.2' }, f.stable.specs)
    assert_equal({ :tag => '0.3' }, f.devel.specs)
    assert f.head.specs.empty?
  end

  def test_revised_bottle_specs
    f = RevisedBottleSpecTestBall.new

    assert_equal 1, f.bottle.revision
    assert_equal case MacOS.cat
      when :snow_leopard_32 then 'deadbeef'*5
      when :snow_leopard    then 'faceb00k'*5
      when :lion            then 'baadf00d'*5
      when :mountain_lion   then '8badf00d'*5
      end, f.bottle.checksum.hexdigest
  end

  def test_custom_version_scheme
    f = CustomVersionSchemeTestBall.new

    assert_version_equal '1.0', f.version
    assert_instance_of CustomVersionScheme, f.version
  end
end
