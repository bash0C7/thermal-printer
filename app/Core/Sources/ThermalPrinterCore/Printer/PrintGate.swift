import Foundation

public enum PrintDecision: Equatable, Sendable {
    case ignore
    case printNow
    case confirmLongPrint
}

public struct PrintGate: Equatable, Sendable {
    public let previewReady: Bool
    public let rows: Int
    public let isPrinting: Bool
    public let isRefreshingStatus: Bool
    public let pendingCards: Int

    public init(previewReady: Bool, rows: Int, isPrinting: Bool, isRefreshingStatus: Bool, pendingCards: Int) {
        self.previewReady = previewReady
        self.rows = rows
        self.isPrinting = isPrinting
        self.isRefreshingStatus = isRefreshingStatus
        self.pendingCards = pendingCards
    }

    public var canPrint: Bool {
        previewReady && rows > 0 && !isPrinting && !isRefreshingStatus && pendingCards == 0
    }

    public func decision(policy: LengthPolicy) -> PrintDecision {
        guard canPrint else { return .ignore }
        return policy.isTooLong(rows: rows) ? .confirmLongPrint : .printNow
    }
}
