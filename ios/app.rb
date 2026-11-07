class PrinterApp
  def run_cli(arg)
    args = arg.split("\t")
    lock = args.shift
    factory = lambda { PhomemoThermalPrinter::Transport.new }
    code = PhomemoCLI::Runner.new(args, transport_factory: factory, lock_path: lock).run
    "exit=#{code}"
  end

  def hold(arg)
    args = arg.split("\t")
    timeout = PhomemoCLI::Holder::LOOP_TIMEOUT_MS
    factory = lambda { PhomemoThermalPrinter::Transport.new(loop_timeout_ms: timeout) }
    PhomemoCLI::Holder.new(args[0], transport_factory: factory, density: args[1].to_i).run
  end

  def tick(_arg)
    ""
  end
end

App = PrinterApp.new
