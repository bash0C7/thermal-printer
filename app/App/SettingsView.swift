import SwiftUI
import ThermalPrinterCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Stepper(
                "長さの警告のしきい値: \(String(format: "%g", model.thresholdCentimeters)) cm",
                value: Binding(get: { model.thresholdCentimeters }, set: { model.setThreshold($0) }),
                in: 5...200, step: 5
            )
            .accessibilityIdentifier("thresholdStepper")
        }
        .padding(20)
        .frame(width: 380)
    }
}
