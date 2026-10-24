import Foundation

public struct PrintResult: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case print
        case status
        case dryRun = "dry_run"
    }

    public enum ErrorKind: String, Codable, CaseIterable, Sendable {
        case unknown
        case usage
        case invalidInput = "invalid_input"
        case notFound = "not_found"
        case wrongDevice = "wrong_device"
        case busy
        case timeout
        case disconnected
        case statusUnavailable = "status_unavailable"
        case paperOut = "paper_out"
        case coverOpen = "cover_open"
        case overheat
        case lowBattery = "low_battery"
        case printFailed = "print_failed"
        case canceled

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = ErrorKind(rawValue: raw) ?? .unknown
        }
    }

    public struct Status: Codable, Equatable, Sendable {
        public var battery: Int?
        public var paper: String?
        public var cover: String?
        public var temperature: String?
        public var firmware: String?
        public var serial: String?
        public var autoOff: Int?

        public init(battery: Int?, paper: String?, cover: String?, temperature: String?,
                    firmware: String?, serial: String?, autoOff: Int?) {
            self.battery = battery
            self.paper = paper
            self.cover = cover
            self.temperature = temperature
            self.firmware = firmware
            self.serial = serial
            self.autoOff = autoOff
        }

        enum CodingKeys: String, CodingKey {
            case battery, paper, cover, temperature, firmware, serial
            case autoOff = "auto_off"
        }
    }

    public struct Job: Codable, Equatable, Sendable {
        public var rows: Int
        public var blocks: Int
        public var bytes: Int
        public var chunks: Int
        public var chunkSize: Int
        public var intervalMs: Int
        public var density: Int

        enum CodingKeys: String, CodingKey {
            case rows, blocks, bytes, chunks, density
            case chunkSize = "chunk_size"
            case intervalMs = "interval_ms"
        }
    }

    public struct Notify: Codable, Equatable, Sendable {
        public var acks: Int
        public var maxWrite: Int?
        public var events: [String]

        enum CodingKeys: String, CodingKey {
            case acks, events
            case maxWrite = "max_write"
        }
    }

    public struct Completion: Codable, Equatable, Sendable {
        public var state: String
        public var afterSendMs: Int?

        enum CodingKeys: String, CodingKey {
            case state
            case afterSendMs = "after_send_ms"
        }
    }

    public var version: Int
    public var mode: Mode
    public var ok: Bool
    public var error: ErrorKind?
    public var exitCode: Int
    public var hint: String?
    public var warnings: [String]
    public var status: Status?
    public var job: Job?
    public var notify: Notify?
    public var completion: Completion?
    public var elapsedMs: Int

    enum CodingKeys: String, CodingKey {
        case version, mode, ok, error, hint, warnings, status, job, notify, completion
        case exitCode = "exit_code"
        case elapsedMs = "elapsed_ms"
    }
}
