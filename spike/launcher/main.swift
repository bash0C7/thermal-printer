import Foundation

let resources = Bundle.main.resourceURL!
let picoruby = resources.appendingPathComponent("picoruby")
var args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty {
    args = [resources.appendingPathComponent("scan.rb").path]
}

let process = Process()
process.executableURL = picoruby
process.arguments = args
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError

do {
    try process.run()
} catch {
    FileHandle.standardError.write(Data("launcher: failed to start picoruby: \(error)\n".utf8))
    exit(127)
}
process.waitUntilExit()

switch process.terminationReason {
case .exit:
    exit(process.terminationStatus)
case .uncaughtSignal:
    FileHandle.standardError.write(Data("launcher: picoruby killed by signal \(process.terminationStatus)\n".utf8))
    exit(128 + process.terminationStatus)
@unknown default:
    exit(1)
}
