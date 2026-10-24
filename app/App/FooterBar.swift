import SwiftUI
import ThermalPrinterCore

struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Text("長さ \(model.lengthText)")
                .font(.headline)
                .accessibilityIdentifier("lengthLabel")
            if let warning = model.lengthWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("lengthWarning")
            }
            Spacer()
            if model.isPrinting {
                ProgressView().controlSize(.small)
                Text("印刷中…").accessibilityIdentifier("printingLabel")
            }
            Picker("濃度", selection: $model.density) {
                ForEach(AppModel.densityRange, id: \.self) { level in
                    Text(Self.densityLabel(level)).tag(level)
                }
            }
            .fixedSize()
            .accessibilityIdentifier("densityPicker")
            Button("印刷") { model.requestPrint() }
                .keyboardShortcut("p")
                .buttonStyle(.borderedProminent)
                .disabled(!model.canPrint)
                .accessibilityIdentifier("printButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .confirmationDialog(
            "長い印刷です", isPresented: $model.confirmingLongPrint, titleVisibility: .visible
        ) {
            Button("印刷する") { Task { await model.printStrip() } }
                .accessibilityIdentifier("confirmPrintButton")
            Button("やめる", role: .cancel) {}
                .accessibilityIdentifier("cancelPrintButton")
        } message: {
            Text(model.lengthWarning ?? "長さ \(model.lengthText)")
        }
    }

    static func densityLabel(_ level: Int) -> String {
        switch level {
        case 1: "1（薄）"
        case AppModel.defaultDensity: "\(level)（既定）"
        case 5: "5（濃）"
        default: "\(level)"
        }
    }
}
