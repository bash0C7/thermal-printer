import Observation
import SwiftUI
import ThermalPrinterCore
import UIKit

@MainActor
@Observable
final class ChekiModel {
    static let shownAfterShot = Duration.seconds(1)
    static let revealStep = Duration.milliseconds(33)

    private(set) var isActive = false
    private(set) var isBusy = false
    private(set) var monochrome: UIImage?
    private(set) var revealedFraction = 0.0

    @ObservationIgnored let camera = ChekiCamera()

    func toggle() {
        if isActive {
            pause()
            isActive = false
        } else {
            isActive = true
            resume()
        }
    }

    func resume() {
        guard isActive else { return }
        camera.start()
        VMPrinter.shared.startHolding(density: PhoneModel.density)
    }

    func suspend() {
        guard isActive else { return }
        pause()
    }

    func shoot() async {
        guard !isBusy else { return }
        isBusy = true
        defer {
            monochrome = nil
            revealedFraction = 0
            isBusy = false
        }
        guard let data = await camera.capture() else { return }
        let linked = VMPrinter.shared.isHeldLinked
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
        camera.stop()
        VMPrinter.shared.stopHolding()
    }
}

struct ChekiView: View {
    let model: ChekiModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ZStack {
                CameraPreview(camera: model.camera)
                if let image = model.monochrome {
                    Color.white
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .mask(alignment: .top) {
                            GeometryReader { geometry in
                                Rectangle().frame(height: geometry.size.height * model.revealedFraction)
                            }
                        }
                        .accessibilityIdentifier("chekiMonochrome")
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await model.shoot() } }
        .accessibilityIdentifier("chekiView")
    }
}
