import SwiftUI
import ThermalPrinterCore

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            MessageBars()
            NavigationSplitView {
                TodayColumn()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            } content: {
                PartsColumn()
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
            } detail: {
                PreviewColumn()
            }
            FooterBar()
        }
        .navigationTitle("Thermal Printer")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Text(model.status?.line ?? "プリンターの状態は未確認")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(model.status?.detail ?? "")
                    .accessibilityIdentifier("statusLabel")
                Button {
                    Task { await model.refreshStatus() }
                } label: {
                    Label("状態を更新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshingStatus || model.isPrinting)
                .accessibilityIdentifier("refreshStatusButton")
            }
        }
        .background(ScreenReader { model.scale = $0 })
        .task { await model.start() }
        .frame(minWidth: 960, minHeight: 560)
    }
}

struct MessageBars: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let detail = model.status?.detail {
                bar(detail, color: .orange, identifier: "statusDetailLabel", dismiss: nil)
            }
            if let banner = model.banner {
                bar(banner.text, color: color(banner.kind), identifier: "messageLabel") { model.banner = nil }
            }
        }
    }

    private func color(_ kind: Banner.Kind) -> Color {
        switch kind {
        case .success: .green
        case .warning: .orange
        case .failure: .red
        }
    }

    private func bar(_ text: String, color: Color, identifier: String, dismiss: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(identifier)
            if let dismiss {
                Button("閉じる", action: dismiss)
                    .buttonStyle(.link)
                    .accessibilityIdentifier("dismissMessageButton")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.18))
    }
}
