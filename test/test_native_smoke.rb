require_relative 'test_helper'
require 'css/native'

class TestNativeSmoke < Minitest::Test
  def test_native_module_is_defined
    assert defined?(CSS::Native), 'CSS::Native should be defined after require'
  end

  def test_hello_round_trip
    assert_equal 'hello from rust', CSS::Native.hello
  end
end
