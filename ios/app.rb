class PrinterApp
  def run_cli(arg)
    args = arg.split("\t")
    lock = args.shift
    factory = lambda { PhomemoThermalPrinter::Transport.new }
    code = PhomemoCLI::Runner.new(args, transport_factory: factory, lock_path: lock).run
    "exit=#{code}"
  end

  def tick(_arg)
    ""
  end
end

App = PrinterApp.new
