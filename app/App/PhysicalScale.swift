import AppKit
import CoreGraphics
import SwiftUI
import ThermalPrinterCore

extension PhysicalScale {
    @MainActor
    static func of(_ screen: NSScreen) -> PhysicalScale {
        let backing = screen.backingScaleFactor
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return .fallback
        }
        let size = CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value))
        return .measured(pixelsWide: screen.frame.width * backing, millimetersWide: size.width, backingScale: backing)
    }
}

struct ScreenReader: NSViewRepresentable {
    let onChange: @MainActor (PhysicalScale) -> Void

    func makeNSView(context: Context) -> ScreenReaderView {
        let view = ScreenReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ScreenReaderView, context: Context) {
        view.onChange = onChange
        view.report()
    }
}

final class ScreenReaderView: NSView {
    var onChange: (@MainActor (PhysicalScale) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard window != nil else { return }
        let names: [Notification.Name] = [
            NSWindow.didChangeScreenNotification, NSApplication.didChangeScreenParametersNotification,
        ]
        for name in names {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
        }
        report()
    }

    @MainActor
    func report() {
        guard let screen = window?.screen ?? NSScreen.main else { return }
        onChange?(PhysicalScale.of(screen))
    }
}
