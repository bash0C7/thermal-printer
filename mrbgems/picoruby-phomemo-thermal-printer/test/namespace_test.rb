class NamespaceTest < Picotest::Test
  def test_format_error_is_a_gem_error
    assert_equal PhomemoThermalPrinter::Error, PhomemoThermalPrinter::FormatError.superclass
  end
end
