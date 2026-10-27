import SwiftUI
import ThermalPrinterCore

@main
struct ThermalPrinterPhoneApp: App {
    @State private var model = PhoneModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .task {
                    VMPrinter.shared.warmUp()
                    if CommandLine.arguments.contains("-DryRunSelfTest") { await Self.dryRunSelfTest() }
                }
        }
    }

    private static func dryRunSelfTest() async {
        let bitmap = StripComposer().compose([.text("self test")]).bitmap
        do {
            let result = try await VMPrinter.shared.dryRun(bitmap)
            NSLog("[ThermalPrinterPhone] dry-run ok=%d rows=%d", result.ok ? 1 : 0, result.job?.rows ?? -1)
        } catch {
            NSLog("[ThermalPrinterPhone] dry-run failed: %@", error.localizedDescription)
        }
    }
}
