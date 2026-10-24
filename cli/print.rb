root = ARGV[0]
load "#{root}/cli/phomemo_cli.rb"

factory = nil
if defined?(PhomemoThermalPrinter::Darwin::Transport)
  factory = lambda { PhomemoThermalPrinter::Darwin::Transport.new }
end

exit PhomemoCLI::Runner.new(ARGV[1, ARGV.size - 1], transport_factory: factory).run
