require 'machine'
require "watchdog"
Watchdog.disable
require "shell"
STDIN = IO.new
STDOUT = IO.new

begin
  STDIN.echo = false
  Shell.setup_root_volume(:flash, label: 'storage')
rescue => e
  puts "#{e.message} (#{e.class})"
rescue Exception => e
  puts "FATAL: #{e.message} (#{e.class})"
end

begin
  if File.exist?("/home/app.mrb")
    GC.start
    puts "Loading app.mrb"
    load "/home/app.mrb"
  end
rescue => e
  puts "app.mrb failed: #{e.message} (#{e.class})"
rescue Exception => e
  puts "app.mrb FATAL: #{e.message} (#{e.class})"
end

begin
  Shell.setup_system_files
  GC.start

  $shell = Shell.new(clean: true)
  puts "Starting shell...\n\n"

  $shell.show_logo
  $shell.start
rescue => e
  puts "#{e.message} (#{e.class})"
rescue Exception => e
  puts "FATAL: #{e.message} (#{e.class})"
end
