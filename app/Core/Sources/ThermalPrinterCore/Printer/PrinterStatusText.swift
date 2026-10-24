import Foundation

public struct PrinterStatusSnapshot: Equatable, Sendable {
    public var line: String
    public var detail: String?

    public init(line: String, detail: String? = nil) {
        self.line = line
        self.detail = detail
    }
}

public enum PrinterStatusText {
    public static func message(for kind: PrintResult.ErrorKind) -> String {
        switch kind {
        case .unknown:
            "予期しないエラーで処理が終わりました。もう一度試してください。"
        case .usage:
            "CLIの引数が正しくありません。"
        case .invalidInput:
            "画像を読めませんでした。幅384 dotの1bitのPBMか確認してください。"
        case .notFound:
            "プリンター（T02）が見つかりません。電源ボタンを押して起こし、公式アプリの接続を切ってから、もう一度試してください。Bluetoothの許可も確認してください。"
        case .wrongDevice:
            "T02ではない機器に当たりました。何も送っていません。"
        case .busy:
            "別の印刷または状態確認が実行中です。終わってからもう一度試してください。"
        case .timeout:
            "接続が時間内に終わりませんでした。プリンターの電源と距離を確認して、もう一度試してください。"
        case .disconnected:
            "送信中にプリンターとの接続が切れました。電源と距離を確認して、もう一度試してください。"
        case .statusUnavailable:
            "プリンターから状態の応答がありません。電源を入れ直して、もう一度試してください。"
        case .paperOut:
            "紙がありません。紙を入れてから、もう一度試してください。"
        case .coverOpen:
            "カバーが開いています。閉じてから、もう一度試してください。"
        case .overheat:
            "プリンターが高温です。冷めるまで待ってから、もう一度試してください。"
        case .lowBattery:
            "電池が残りわずか（5%以下）です。充電してから、もう一度試してください。"
        case .printFailed:
            "プリンターが印刷の失敗を返しました。紙とカバーを確認して、もう一度試してください。"
        case .canceled:
            "プリンター側で印刷が取り消されました。"
        }
    }

    public static func warningMessage(_ warning: String) -> String {
        switch warning {
        case "status_unavailable":
            "プリンターの状態を確認できないまま印刷しました。"
        case "completion_unconfirmed":
            "完了の通知が届きませんでした。印字結果を確かめてください。"
        case "battery_low":
            "電池が少なくなっています（10%以下）。"
        default:
            warning
        }
    }

    public static func titleBar(_ status: PrintResult.Status, checkedAt: Date,
                                calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let battery = status.battery { parts.append("電池\(battery)%") }
        if let paper = status.paper { parts.append(paperText(paper)) }
        if let cover = status.cover { parts.append(coverText(cover)) }
        if let temperature = status.temperature { parts.append(temperatureText(temperature)) }
        let body = parts.isEmpty ? "状態不明" : parts.joined(separator: "・")
        return "\(body)（\(clock(checkedAt, calendar))確認）"
    }

    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func paperText(_ value: String) -> String {
        switch value {
        case "ok": "紙あり"
        case "out": "紙なし"
        default: "紙\(value)"
        }
    }

    private static func coverText(_ value: String) -> String {
        switch value {
        case "closed": "カバー閉"
        case "open": "カバー開"
        default: "カバー\(value)"
        }
    }

    private static func temperatureText(_ value: String) -> String {
        switch value {
        case "normal": "温度正常"
        case "overheat": "温度過熱"
        default: "温度\(value)"
        }
    }
}
