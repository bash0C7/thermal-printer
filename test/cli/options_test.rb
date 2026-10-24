class OptionsTest < Picotest::Test
  def parse(argv, env = {})
    PhomemoCLI::Options.parse(argv, env: env)
  end

  def test_defaults_follow_the_design
    o = parse(["a.pbm"])
    assert_nil o.error
    assert_equal "T02", o.device
    assert_equal 4, o.density
    assert_equal 128, o.chunk
    assert_equal 20, o.interval
    assert_equal "a.pbm", o.pbm
    assert_nil o.result
    assert_false o.dry_run
    assert_false o.status
  end

  def test_every_option_is_read
    o = parse(["--device", "T02X", "--density", "2", "--chunk", "64", "--interval", "50",
               "--result", "/tmp/r.json", "--dry-run", "a.pbm"])
    assert_nil o.error
    assert_equal "T02X", o.device
    assert_equal 2, o.density
    assert_equal 64, o.chunk
    assert_equal 50, o.interval
    assert_equal "/tmp/r.json", o.result
    assert_true o.dry_run
    assert_equal "a.pbm", o.pbm
  end

  def test_options_may_follow_the_pbm
    o = parse(["a.pbm", "--density", "5"])
    assert_nil o.error
    assert_equal 5, o.density
    assert_equal "a.pbm", o.pbm
  end

  def test_chunk_is_accepted_from_20_to_182
    assert_nil parse(["--chunk", "20", "a.pbm"]).error
    assert_nil parse(["--chunk", "182", "a.pbm"]).error
    assert_equal :usage, parse(["--chunk", "19", "a.pbm"]).error
    assert_equal :usage, parse(["--chunk", "183", "a.pbm"]).error
  end

  def test_interval_is_accepted_from_10_to_1000
    assert_nil parse(["--interval", "10", "a.pbm"]).error
    assert_nil parse(["--interval", "1000", "a.pbm"]).error
    assert_equal :usage, parse(["--interval", "9", "a.pbm"]).error
    assert_equal :usage, parse(["--interval", "1001", "a.pbm"]).error
  end

  def test_density_is_accepted_from_1_to_5
    assert_nil parse(["--density", "1", "a.pbm"]).error
    assert_nil parse(["--density", "5", "a.pbm"]).error
    assert_equal :usage, parse(["--density", "0", "a.pbm"]).error
    assert_equal :usage, parse(["--density", "6", "a.pbm"]).error
  end

  def test_a_value_that_is_not_a_plain_integer_is_a_usage_error
    assert_equal :usage, parse(["--chunk", "abc", "a.pbm"]).error
    assert_equal :usage, parse(["--chunk", "12x", "a.pbm"]).error
    assert_equal :usage, parse(["--chunk", "-5", "a.pbm"]).error
    assert_equal :usage, parse(["--chunk", "", "a.pbm"]).error
  end

  def test_an_option_without_its_value_is_a_usage_error
    assert_equal :usage, parse(["a.pbm", "--chunk"]).error
    assert_equal :usage, parse(["a.pbm", "--device"]).error
    assert_equal :usage, parse(["a.pbm", "--result"]).error
  end

  def test_an_empty_device_or_result_is_a_usage_error
    assert_equal :usage, parse(["--device", "", "a.pbm"]).error
    assert_equal :usage, parse(["--result", "", "a.pbm"]).error
    assert_not_nil parse(["--device", "", "a.pbm"]).message
  end

  def test_status_needs_no_pbm_but_print_does
    o = parse(["--status"])
    assert_nil o.error
    assert_true o.status
    assert_nil o.pbm
    assert_equal :usage, parse([]).error
  end

  def test_status_with_a_pbm_is_a_usage_error
    assert_equal :usage, parse(["--status", "a.pbm"]).error
  end

  def test_status_accepts_device_and_result
    o = parse(["--status", "--device", "T02", "--result", "/tmp/s.json"])
    assert_nil o.error
    assert_equal "/tmp/s.json", o.result
  end

  def test_unknown_option_and_extra_positional_are_usage_errors
    assert_equal :usage, parse(["--bogus", "a.pbm"]).error
    assert_equal :usage, parse(["a.pbm", "b.pbm"]).error
  end

  def test_a_usage_error_carries_a_message
    assert_not_nil parse(["--chunk", "183", "a.pbm"]).message
  end

  def test_feed_comes_from_the_environment_within_esc_d_range
    assert_equal 1, parse(["a.pbm"], {}).feed
    assert_equal 6, parse(["a.pbm"], {"PHOMEMO_FEED" => "6"}).feed
    assert_equal 0, parse(["a.pbm"], {"PHOMEMO_FEED" => "0"}).feed
    assert_equal 255, parse(["a.pbm"], {"PHOMEMO_FEED" => "255"}).feed
    assert_equal :usage, parse(["a.pbm"], {"PHOMEMO_FEED" => "256"}).error
    assert_equal :usage, parse(["a.pbm"], {"PHOMEMO_FEED" => "x"}).error
  end

  def test_feed_has_no_command_line_option
    assert_equal :usage, parse(["--feed", "6", "a.pbm"]).error
  end
end
