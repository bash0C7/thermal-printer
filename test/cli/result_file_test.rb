require 'json'

class ResultFileTest < Picotest::Test
  FIXTURES = ["result_print_ok.json", "result_status_ok.json", "result_not_found.json"]

  def fixture_path(name)
    File.join(ENV["THERMAL_PRINTER_REPO_ROOT"], "test", "fixtures", name)
  end

  def read_fixture(name)
    JSON.parse(File.open(fixture_path(name), "r") { |f| f.read })
  end

  def tmp_path(name)
    @paths = [] unless @paths
    path = "/tmp/phomemo-cli-resulttest-#{name}-#{Machine.board_millis}.json"
    @paths << path
    @paths << path + ".tmp"
    path
  end

  def teardown
    return unless @paths
    i = 0
    while i < @paths.size
      File.delete(@paths[i]) if File.exist?(@paths[i])
      i += 1
    end
    @paths = []
  end

  def test_written_result_round_trips_the_contract_fixture
    path = tmp_path("ok")
    expected = read_fixture("result_print_ok.json")
    PhomemoCLI::ResultFile.write(path, expected)
    written = JSON.parse(File.open(path, "r") { |f| f.read })
    assert_equal expected, written
    assert_equal expected.keys.sort, written.keys.sort
    assert_false File.exist?(path + ".tmp")
  end

  def test_an_existing_result_is_replaced
    path = tmp_path("replace")
    PhomemoCLI::ResultFile.write(path, read_fixture("result_print_ok.json"))
    PhomemoCLI::ResultFile.write(path, read_fixture("result_not_found.json"))
    written = JSON.parse(File.open(path, "r") { |f| f.read })
    assert_equal "not_found", written["error"]
    assert_false File.exist?(path + ".tmp")
  end

  def test_all_fixtures_share_the_same_keys
    keys = read_fixture("result_print_ok.json").keys.sort
    assert_equal ["completion", "elapsed_ms", "error", "exit_code", "hint", "job", "mode", "notify", "ok", "status", "version", "warnings"], keys
    assert_equal keys, read_fixture("result_status_ok.json").keys.sort
    assert_equal keys, read_fixture("result_not_found.json").keys.sort
  end

  def test_fixture_exit_codes_agree_with_the_table
    i = 0
    while i < FIXTURES.size
      r = read_fixture(FIXTURES[i])
      expected = r["error"] ? PhomemoCLI::EXIT_CODES[r["error"]] : 0
      assert_equal expected, r["exit_code"]
      assert_equal r["error"].nil?, r["ok"]
      i += 1
    end
  end

  def test_every_error_kind_has_a_distinct_exit_code
    codes = PhomemoCLI::EXIT_CODES.values
    assert_equal codes.size, codes.uniq.size
    assert_equal 10, PhomemoCLI::EXIT_CODES["not_found"]
  end

  def test_exit_codes_follow_the_contract_table
    expected = {
      "unknown" => 1, "usage" => 2, "not_found" => 10, "wrong_device" => 11, "busy" => 12,
      "timeout" => 13, "disconnected" => 14, "status_unavailable" => 15,
      "paper_out" => 20, "cover_open" => 21, "overheat" => 22, "low_battery" => 23,
      "print_failed" => 30, "canceled" => 31,
    }
    assert_equal expected, PhomemoCLI::EXIT_CODES
  end

  def test_exit_code_for_maps_success_and_the_invalid_input_alias
    assert_equal 0, PhomemoCLI.exit_code_for(nil)
    assert_equal 2, PhomemoCLI.exit_code_for("usage")
    assert_equal 2, PhomemoCLI.exit_code_for("invalid_input")
    assert_equal 12, PhomemoCLI.exit_code_for("busy")
    assert_equal 1, PhomemoCLI.exit_code_for("something_new")
  end
end
