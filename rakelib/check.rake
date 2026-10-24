module SendPathCheck
  SELF = "rakelib/check.rake"

  RULES = {
    "write_value_of_characteristic" => [],
    "write_chunk" => [],
    /\b(?:public_send|__send__|send)\b/ => %w[tools/make_test_pbm.rb],
    "method(" => [],
    "@event_queue" => [],
    "_event_popped" => [],
    "@conn_handle" => [],
    "@services" => [],
    "@write_values" => [],
    "@read_values" => [],
    "HCI_CON_HANDLE_INVALID" => [],
  }.freeze

  GLOBS = %w[cli/**/*.rb tools/**/*.rb bin/* rakelib/**/*.rake].freeze

  def self.files(root)
    found = GLOBS.flat_map { |g| Dir[File.join(root, g)] }.uniq.sort
    found = found.select { |f| File.file?(f) }
    found.map { |f| f.delete_prefix("#{root}/") }
         .reject { |rel| rel == SELF || rel.split(File::SEPARATOR).include?("test") }
  end

  def self.violations(root)
    found = []
    files(root).each do |rel|
      File.foreach(File.join(root, rel)).with_index(1) do |line, no|
        RULES.each do |needle, allowed|
          hit = needle.is_a?(Regexp) ? line.match?(needle) : line.include?(needle)
          next unless hit
          next if allowed.include?(rel)
          found << "#{rel}:#{no}: #{needle.is_a?(Regexp) ? "dynamic send" : needle}"
        end
      end
    end
    found
  end
end

namespace :check do
  desc "Fail when a BLE write call appears outside the allowed places (this repo, then the phomemo gem)"
  task :send_paths do
    violations = SendPathCheck.violations(ROOT)
    abort "[check] send paths violated:\n  #{violations.join("\n  ")}" unless violations.empty?
    abort "#{GEM_DIR} not found - run `rake vendor:setup` first" unless Dir.exist?(GEM_DIR)
    sh "rake", "-C", GEM_DIR, "check:send_paths"
    puts "[check] send paths ok"
  end
end
