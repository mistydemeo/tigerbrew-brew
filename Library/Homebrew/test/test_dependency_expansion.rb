require 'testing_env'
require 'dependency'

class DependencyExpansionTests < Test::Unit::TestCase
  def build_dep(name, deps=[])
    dep = Dependency.new(name)
    dep.stubs(:to_formula).returns(stub(:deps => deps))
    dep
  end

  def setup
    @foo = build_dep(:foo)
    @bar = build_dep(:bar)
    @baz = build_dep(:baz)
    @qux = build_dep(:qux)
    @deps = [@foo, @bar, @baz, @qux]
    @f    = stub(:deps => @deps)
  end

  def test_expand_yields_dependent_and_dep_pairs
    i = 0
    Dependency.expand(@f) do |dependent, dep|
      assert_equal @f, dependent
      assert_equal dep, @deps[i]
      i += 1
    end
  end

  def test_expand_no_block
    assert_equal @deps, Dependency.expand(@f)
  end

  def test_expand_prune_all
    assert_empty Dependency.expand(@f) { Dependency.prune }
  end

  def test_expand_selective_pruning
    deps = Dependency.expand(@f) do |_, dep|
      Dependency.prune if dep.name == :foo
    end

    assert_equal [@bar, @baz, @qux], deps
  end

  def test_expand_preserves_dependency_order
    @foo.stubs(:to_formula).returns(stub(:deps => [@qux, @baz]))
    assert_equal [@qux, @baz, @foo, @bar], Dependency.expand(@f)
  end

  def test_expand_skips_optionals_by_default
    @foo.expects(:optional?).returns(true)
    @f = stub(:deps => @deps, :build => stub(:with? => false))
    assert_equal [@bar, @baz, @qux], Dependency.expand(@f)
  end

  def test_expand_keeps_recommendeds_by_default
    @foo.expects(:recommended?).returns(true)
    @f = stub(:deps => @deps, :build => stub(:with? => true))
    assert_equal @deps, Dependency.expand(@f)
  end
end
