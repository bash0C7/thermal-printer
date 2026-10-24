import Foundation
import Observation

@MainActor
@Observable
public final class PreviewCoordinator {
    public enum Phase {
        case empty
        case generating
        case ready(CLIPreview)
        case failed(String)
    }

    public private(set) var phase: Phase = .empty

    @ObservationIgnored private let client: PrinterClient
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pending: [Task<Void, Never>] = []
    @ObservationIgnored private var printing: URL?

    public init(client: PrinterClient) {
        self.client = client
    }

    public var readyPreview: CLIPreview? {
        guard case let .ready(preview) = phase else { return nil }
        return preview
    }

    public var isGenerating: Bool {
        guard case .generating = phase else { return false }
        return true
    }

    public var failureMessage: String? {
        guard case let .failed(message) = phase else { return nil }
        return message
    }

    public func update(_ bitmap: Bitmap1) {
        generation += 1
        let token = generation
        discardReady()
        guard bitmap.height > 0 else {
            phase = .empty
            return
        }
        phase = .generating
        let client = client
        pending.append(Task {
            do {
                accept(try await client.preview(bitmap), token: token)
            } catch {
                reject(error, token: token)
            }
        })
    }

    public func invalidate() {
        generation += 1
        discardReady()
        phase = .generating
    }

    public func fail(_ message: String) {
        generation += 1
        discardReady()
        phase = .failed(message)
    }

    public func printReady(density: Int) async throws -> PrintResult {
        guard let preview = readyPreview else { throw PrinterClientError.previewNotReady }
        printing = preview.pbm
        defer {
            printing = nil
            if readyPreview?.pbm != preview.pbm { remove(preview.pbm) }
        }
        return try await client.print(pbm: preview.pbm, density: density)
    }

    public func waitUntilSettled() async {
        while !pending.isEmpty {
            let batch = pending
            pending = []
            for task in batch { await task.value }
        }
    }

    private func accept(_ preview: CLIPreview, token: Int) {
        guard token == generation else {
            remove(preview.pbm)
            return
        }
        phase = .ready(preview)
    }

    private func reject(_ error: Error, token: Int) {
        guard token == generation else { return }
        phase = .failed(error.localizedDescription)
    }

    private func discardReady() {
        guard let preview = readyPreview, preview.pbm != printing else { return }
        remove(preview.pbm)
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
