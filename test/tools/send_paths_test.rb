require "minitest/autorun"
require "rake"
require "tmpdir"
require "fileutils"

load File.expand_path("../../rakelib/check.rake", __dir__)

class SendPathsTest < Minitest::Test
  SESSION = "mrbgems/picoruby-phomemo-thermal-printer/mrblib/phomemo_thermal_printer/session.rb"
  TRANSPORT = "mrbgems/picoruby-phomemo-thermal-printer/ports/darwin/transport.rb"
  CLEAN_SESSION = "class S\n  def emit(bytes)\n    @transport.write_chunk(bytes)\n  end\nend\n"

  def tree
    Dir.mktmpdir do |root|
      put(root, SESSION, CLEAN_SESSION)
      yield root
    end
  end

  def put(root, rel, text)
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def test_the_clean_layout_has_no_violation
    tree { |root| assert_equal [], SendPathCheck.violations(root) }
  end

  def test_the_transport_may_call_the_ble_write
    tree do |root|
      put(root, TRANSPORT, "x.write_value_of_characteristic_without_response(h, d)\nx.write_chunk(d)\n")
      assert_equal [], SendPathCheck.violations(root)
    end
  end

  def test_a_second_write_chunk_in_the_session_is_a_violation
    tree do |root|
      put(root, SESSION, CLEAN_SESSION + "class T\n  def other(b)\n    @transport.write_chunk(b)\n  end\nend\n")
      assert_equal 1, SendPathCheck.violations(root).size
    end
  end

  def test_a_write_chunk_in_the_session_outside_emit_is_a_violation
    tree do |root|
      put(root, SESSION, "class S\n  def other(bytes)\n    @transport.write_chunk(bytes)\n  end\nend\n")
      assert_equal 1, SendPathCheck.violations(root).size
    end
  end

  def test_a_session_without_any_write_chunk_is_a_violation
    tree do |root|
      put(root, SESSION, "class S\nend\n")
      assert_equal 1, SendPathCheck.violations(root).size
    end
  end

  def test_a_write_chunk_in_another_gem_file_is_a_violation
    tree do |root|
      put(root, "mrbgems/picoruby-phomemo-thermal-printer/mrblib/phomemo_thermal_printer/other.rb", "t.write_chunk(b)\n")
      assert_equal 1, SendPathCheck.violations(root).size
    end
  end

  def test_dynamic_dispatch_forms_are_violations
    forms = [
      "t.send(:write_chunk, b)",
      "t.send :write_chunk, b",
      "t.send \"write_\" + name, b",
      "t.public_send(name, b)",
      "t.__send__(name, b)",
      "t.method(:x)",
    ]
    forms.each do |form|
      tree do |root|
        put(root, "cli/probe.rb", "#{form}\n")
        refute_empty SendPathCheck.violations(root), form
      end
    end
  end

  def test_names_that_only_start_with_send_are_not_violations
    tree do |root|
      put(root, "cli/probe.rb", "def send_job(job)\n  send_chunks(job)\nend\n")
      assert_equal [], SendPathCheck.violations(root)
    end
  end

  def test_rake_files_are_scanned
    tree do |root|
      put(root, "rakelib/probe.rake", "t.public_send(:x)\n")
      assert_equal 1, SendPathCheck.violations(root).size
    end
  end

  def test_the_checker_itself_is_not_scanned
    tree do |root|
      put(root, "rakelib/check.rake", "NEEDLES = ['send(', 'write_chunk']\n")
      assert_equal [], SendPathCheck.violations(root)
    end
  end

  def test_spike_and_test_directories_are_skipped_but_names_that_merely_contain_test_are_not
    tree do |root|
      put(root, "spike/probe.rb", "t.send(:x)\n")
      put(root, "mrbgems/g/test/probe.rb", "t.send(:x)\n")
      assert_equal [], SendPathCheck.violations(root)
      put(root, "mrbgems/g/mrblib/testing.rb", "t.send(:x)\n")
      assert_equal 1, SendPathCheck.violations(root).size
    end
  end

  def test_library_internals_are_never_touched
    ["@event_queue.pop", "_event_popped", "@conn_handle = 1", "@services.clear", "HCI_CON_HANDLE_INVALID",
     "@write_values", "@read_values"].each do |text|
      tree do |root|
        put(root, TRANSPORT, "class T\n  def x\n    #{text}\n  end\nend\n")
        found = SendPathCheck.violations(root)
        assert_equal 1, found.size, text
        assert_includes found[0], TRANSPORT
      end
    end
  end

  def test_the_real_tree_is_clean
    assert_equal [], SendPathCheck.violations(File.expand_path("../..", __dir__))
  end
end
