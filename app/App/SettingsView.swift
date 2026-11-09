import SwiftUI
import ThermalPrinterCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var vaultPathText = ""

    var body: some View {
        Form {
            Stepper(
                "長さの警告のしきい値: \(String(format: "%g", model.thresholdCentimeters)) cm",
                value: Binding(get: { model.thresholdCentimeters }, set: { model.setThreshold($0) }),
                in: 5...200, step: 5
            )
            .accessibilityIdentifier("thresholdStepper")
            TextField("TaskForge の vault の場所", text: $vaultPathText)
                .onSubmit {
                    model.setVaultPath(vaultPathText)
                    vaultPathText = model.vaultPath
                }
                .onAppear { vaultPathText = model.vaultPath }
                .accessibilityIdentifier("vaultPathField")
        }
        .padding(20)
        .frame(width: 380)
    }
}
