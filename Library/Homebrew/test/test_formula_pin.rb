require 'testing_env'
require 'formula_pin'

class FormulaPinTests < Test::Unit::TestCase
  class FormulaDouble
    def name
      "double"
    end

    def rack
      Pathname.new("#{HOMEBREW_CELLAR}/#{name}")
    end
  end

  def setup
    @f   = FormulaDouble.new
    @pin = FormulaPin.new(@f)
    @f.rack.mkpath
  end

  def test_not_pinnable
    assert !@pin.pinnable?
  end

  def test_pinnable_if_kegs_exist
    (@f.rack+'0.1').mkpath
    assert @pin.pinnable?
  end

  def test_pin
    (@f.rack+'0.1').mkpath
    @pin.pin
    assert @pin.pinned?
    assert_equal 1, FormulaPin::PINDIR.children.length
  end

  def test_unpin
    (@f.rack+'0.1').mkpath
    @pin.pin
    @pin.unpin
    assert !@pin.pinned?
    assert_equal 0, FormulaPin::PINDIR.children.length
  end

  def teardown
    @f.rack.rmtree
  end
end
