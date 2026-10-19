import Foundation

/// 앱·Screen Time 확장들이 App Group으로 나누는 폰 사용 상태
enum ScreenTimeShared {
    static let suite = "group.com.rymchoi.momuri"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: suite) }

    enum DayStatus: String {
        case normal, warning, exceeded
    }

    static var goalMinutes: Int {
        get { defaults?.integer(forKey: "screenGoalMinutes").nonZero ?? 120 }
        set { defaults?.set(newValue, forKey: "screenGoalMinutes") }
    }

    /// 감시를 시작한 날. 이 날 이후만 "목표 지킴"을 자동 기록한다.
    static var monitoringSince: Date? {
        get { defaults?.object(forKey: "screenMonitoringSince") as? Date }
        set { defaults?.set(newValue, forKey: "screenMonitoringSince") }
    }

    static var selectionData: Data? {
        get { defaults?.data(forKey: "screenSelection") }
        set { defaults?.set(newValue, forKey: "screenSelection") }
    }

    static func status(on day: Date) -> DayStatus {
        DayStatus(rawValue: defaults?.string(forKey: key(day)) ?? "") ?? .normal
    }

    static func mark(_ status: DayStatus, on day: Date) {
        // 초과는 경고로 되돌리지 않는다
        if status == .warning && self.status(on: day) == .exceeded { return }
        defaults?.set(status.rawValue, forKey: key(day))
    }

    static func key(_ day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return "screen-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func label(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return String(localized: "\(m)분") }
        return m == 0 ? String(localized: "\(h)시간") : String(localized: "\(h)시간 \(m)분")
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
