import Observation
import SwiftUI
import ThermalPrinterCore
import UIKit

@MainActor
@Observable
final class ChekiModel {
    static let shownAfterShot = Duration.seconds(1)
    static let revealStep = Duration.milliseconds(33)
    static let stateStep = Duration.milliseconds(250)

    private(set) var isActive = false
    private(set) var isBusy = false
    private(set) var monochrome: UIImage?
    private(set) var revealedFraction = 0.0
    private(set) var openHolds = 0
    private(set) var linkState: String?

    @ObservationIgnored let camera = ChekiCamera()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var holdLive = false
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var isSuspended = false

    var isConnecting: Bool { isActive && linkState != "linked" && linkState != "unlinked" }
    var isClosing: Bool { !isActive && openHolds > 0 }

    func toggle() {
        NSLog("[ThermalPrinterPhone] toggle cheki=%d open_holds=%ld busy=%d", isActive ? 0 : 1, openHolds, isBusy ? 1 : 0)
        if isActive {
            pause()
            isActive = false
        } else {
            isActive = true
            open()
        }
    }

    func resume() {
        guard isActive, isSuspended else { return }
        isSuspended = false
        open()
    }

    func suspend() {
        guard isActive, !isSuspended else { return }
        isSuspended = true
        pause()
    }

    private func open() {
        camera.start()
        generation += 1
        let current = generation
        holdLive = false
        linkState = nil
        openHolds += 1
        VMPrinter.shared.startHolding(
            density: PhoneModel.density,
            started: { [weak self] in
                guard let self, self.generation == current else { return }
                self.holdLive = true
            },
            ended: { [weak self] in
                guard let self else { return }
                self.openHolds -= 1
                if self.generation == current { self.holdLive = false }
            })
        watch?.cancel()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.linkState = self.holdLive ? VMPrinter.shared.holdState() : nil
                try? await Task.sleep(for: Self.stateStep)
            }
        }
    }

    func shoot() async {
        guard !isBusy, !isConnecting else { return }
        isBusy = true
        defer {
            monochrome = nil
            revealedFraction = 0
            isBusy = false
        }
        guard let data = await camera.capture() else { return }
        let linked = holdLive && VMPrinter.shared.holdState() == "linked"
        let shot: ChekiShot
        let png: Data
        do {
            (shot, png) = try await Task.detached(priority: .userInitiated) {
                let shot = try ChekiShot(photoData: data)
                return (shot, try shot.monochromePNG())
            }.value
        } catch {
            NSLog("[ThermalPrinterPhone] shot failed: %@", error.localizedDescription)
            return
        }
        monochrome = UIImage(data: png)
        if linked {
            await PhotoSaver.save(data)
            guard await printShot(shot) else { return }
        } else {
            revealedFraction = 1
            await PhotoSaver.save(png)
        }
        try? await Task.sleep(for: Self.shownAfterShot)
    }

    private func printShot(_ shot: ChekiShot) async -> Bool {
        let start = ContinuousClock.now
        let total = shot.photo.height
        let reveal = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = Int((ContinuousClock.now - start) / .milliseconds(1))
                let rows = ChekiShot.revealedRows(elapsedMs: elapsed, totalRows: total, finished: false)
                revealedFraction = Double(rows) / Double(total)
                try? await Task.sleep(for: Self.revealStep)
            }
        }
        defer { reveal.cancel() }
        do {
            let result = try await VMPrinter.shared.printHeld(shot.strip)
            NSLog("[ThermalPrinterPhone] cheki print ok=%d error=%@ elapsed_ms=%ld", result.ok ? 1 : 0,
                  result.error?.rawValue ?? "-", result.elapsedMs)
            guard result.ok else { return false }
        } catch {
            NSLog("[ThermalPrinterPhone] cheki print failed: %@", error.localizedDescription)
            return false
        }
        reveal.cancel()
        revealedFraction = 1
        return true
    }

    private func pause() {
        generation += 1
        holdLive = false
        watch?.cancel()
        watch = nil
        linkState = nil
        camera.stop()
        VMPrinter.shared.stopHolding()
    }
}

struct ChekiView: View {
    let model: ChekiModel

    var body: some View {
        ZStack {
            Color.black
            CameraPreview(camera: model.camera)
            if let image = model.monochrome {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .mask(alignment: .top) {
                        GeometryReader { geometry in
                            Rectangle().frame(height: geometry.size.height * model.revealedFraction)
                        }
                    }
                    .background(Color.white)
                    .accessibilityIdentifier("chekiMonochrome")
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { linkBadge }
        .contentShape(Rectangle())
        .onTapGesture { Task { await model.shoot() } }
        .onAppear { NSLog("[ThermalPrinterPhone] cheki view appeared") }
        .accessibilityIdentifier("chekiView")
    }

    @ViewBuilder private var linkBadge: some View {
        if model.isConnecting {
            HStack(spacing: 8) {
                ProgressView()
                Text("T02に接続中")
            }
            .badgeStyle()
            .accessibilityIdentifier("chekiConnecting")
        } else if model.linkState == "unlinked" {
            Label("T02に繋がっていません（白黒で保存します）", systemImage: "printer.slash")
                .badgeStyle()
                .accessibilityIdentifier("chekiUnlinked")
        }
    }
}

private extension View {
    func badgeStyle() -> some View {
        font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
    }
}
