require "minitest/autorun"
require "rake"
require "tmpdir"
require "fileutils"

load File.expand_path("../../rakelib/check.rake", __dir__)

class SendPathsTest < Minitest::Test
  def tree
    Dir.mktmpdir do |root|
      put(root, "cli/phomemo_cli.rb", "class C\nend\n")
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

  def test_a_ble_write_in_the_cli_is_a_violation
    ["t.write_chunk(b)", "x.write_value_of_characteristic_without_response(h, d)"].each do |text|
      tree do |root|
        put(root, "cli/probe.rb", "#{text}\n")
        assert_equal 1, SendPathCheck.violations(root).size, text
      end
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

  def test_test_directories_are_skipped_but_names_that_merely_contain_test_are_not
    tree do |root|
      put(root, "tools/test/probe.rb", "t.send(:x)\n")
      assert_equal [], SendPathCheck.violations(root)
      put(root, "cli/testing.rb", "t.send(:x)\n")
      assert_equal 1, SendPathCheck.violations(root).size
    end
  end

  def test_the_real_tree_is_clean
    assert_equal [], SendPathCheck.violations(File.expand_path("../..", __dir__))
  end
end
