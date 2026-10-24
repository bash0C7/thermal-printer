import SwiftUI

@main
struct ThermalPrinterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            ImportFromDevicesCommands()
        }
        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
