import Foundation

enum GrassCell: Hashable {
    case done, empty, scheduled, today, rest
}

enum Urgency: Hashable {
    case none, soon, overdue
}

extension Routine {
    private var cal: Calendar { .current }

    /// 실제로 한 기록 ("쉬기"는 뺀다)
    var activeLogs: [RoutineLog] {
        (logs ?? []).filter { !$0.skipped }
    }

    var doneDays: Set<Date> {
        Set(activeLogs.map { cal.startOfDay(for: $0.date) })
    }

    var startDay: Date { cal.startOfDay(for: createdAt) }

    func logCount(on day: Date) -> Int {
        activeLogs.filter { cal.isDate($0.date, inSameDayAs: day) }.count
    }

    /// 쉬는 요일이거나 그날 "오늘은 쉬기"를 눌렀으면 쉬는 날
    func isRestDay(_ day: Date) -> Bool {
        guard kind == .daily else { return false }
        if restWeekdays.contains(cal.component(.weekday, from: day)) { return true }
        return (logs ?? []).contains { $0.skipped && cal.isDate($0.date, inSameDayAs: day) }
    }

    func isSkipped(on day: Date) -> Bool {
        (logs ?? []).contains { $0.skipped && cal.isDate($0.date, inSameDayAs: day) }
    }

    /// 했거나 쉬기로 한 날 (더 할 일이 없음)
    func isSettled(on day: Date) -> Bool {
        isDone(on: day) || isRestDay(day)
    }

    /// 매일형은 정한 횟수를, 공부는 하루 목표량을 채워야 완료
    func isDone(on day: Date) -> Bool {
        if category == .study { return dayTotal(on: day) >= studyGoal }
        return kind == .daily ? logCount(on: day) >= times.count : doneDays.contains(cal.startOfDay(for: day))
    }

    /// 그날 쌓은 양 (값이 없는 기록은 1)
    func dayTotal(on day: Date) -> Double {
        activeLogs.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + ($1.value ?? 1) }
    }

    /// 알림 시각들(분 단위, 오름차순)
    var times: [Int] {
        reminderTimes.isEmpty ? [reminderHour * 60 + reminderMinute] : reminderTimes.sorted()
    }

    /// 오늘 아직 안 한 다음 시각(분)
    func nextTime(on day: Date) -> Int? {
        let count = logCount(on: day)
        return count < times.count ? times[count] : nil
    }

    static func timeLabel(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 주기형의 다음 예정일(주말 맞춤이면 그 주 토요일). 기록이 없으면 등록일.
    var nextDue: Date? {
        guard kind == .interval else { return nil }
        guard let last = doneDays.max() else {
            return weekendOnly ? (Routine.saturday(ofWeekContaining: startDay) ?? startDay) : startDay
        }
        guard let target = cal.date(byAdding: intervalUnit.component, value: intervalValue, to: last) else { return nil }
        return weekendOnly ? Routine.saturday(ofWeekContaining: target) : target
    }

    /// 이 날까지 하면 늦지 않은 것. 주말 맞춤이면 일요일.
    var dueEnd: Date? {
        guard let due = nextDue else { return nil }
        return weekendOnly ? cal.date(byAdding: .day, value: 1, to: due) : due
    }

    static func saturday(ofWeekContaining day: Date) -> Date? {
        guard let monday = weekCalendar.dateInterval(of: .weekOfYear, for: day)?.start else { return nil }
        return Calendar.current.date(byAdding: .day, value: 5, to: monday)
    }

    func isWithinDueWindow(_ day: Date) -> Bool {
        guard let due = nextDue, let end = dueEnd else { return false }
        let d = cal.startOfDay(for: day)
        return d >= due && d <= end
    }

    func daysUntilDue(from today: Date = .now) -> Int? {
        guard let due = nextDue else { return nil }
        return cal.dateComponents([.day], from: cal.startOfDay(for: today), to: due).day
    }

    /// 해당 날짜의 할 일 목록에 보일지
    func appears(on day: Date, today: Date = .now) -> Bool {
        let d = cal.startOfDay(for: day)
        let t = cal.startOfDay(for: today)
        if isDone(on: d) { return true }
        if kind == .once { return cal.isDate(eventDate, inSameDayAs: d) }
        guard d >= startDay else { return false }
        switch kind {
        case .daily:
            // 쉬는 요일엔 목록에서 빼고, "오늘은 쉬기"는 되돌릴 수 있게 남긴다
            return !restWeekdays.contains(cal.component(.weekday, from: d))
        case .interval:
            guard let due = nextDue else { return false }
            if d == t { return (daysUntilDue(from: t) ?? .max) <= remindDaysBefore }
            return isWithinDueWindow(d) && d >= due
        case .weekly:
            return d == t && !remainingParts(inWeekOf: t).isEmpty
        case .monthly:
            return d == t && monthTotal(of: t) < targetValue
        case .once:
            return cal.isDate(eventDate, inSameDayAs: d)
        }
    }

    func grassCell(on day: Date, today: Date = .now) -> GrassCell {
        let d = cal.startOfDay(for: day)
        if isDone(on: d) { return .done }
        if isRestDay(d) { return .rest }
        if d == cal.startOfDay(for: today) { return .today }
        if isWithinDueWindow(d) { return .scheduled }
        if kind == .once && cal.isDate(eventDate, inSameDayAs: d) { return .scheduled }
        return .empty
    }

    var statusLabel: String {
        switch kind {
        case .daily:
            if category == .diet { return dietStatus }
            if category == .study { return studyProgress(on: .now) + (examLabel.map { " · " + $0 } ?? "") }
            if category == .screen {
                switch ScreenTimeShared.status(on: .now) {
                case .exceeded: return String(localized: "목표 초과")
                case .warning: return String(localized: "80% 넘음")
                case .normal: return String(localized: "목표 \(ScreenTimeShared.label(minutes: goalMinutes))")
                }
            }
            let today = Date.now
            if times.count == 1 { return Routine.timeLabel(times[0]) }
            let count = min(logCount(on: today), times.count)
            return nextTime(on: today).map { "\(count)/\(times.count) · " + Routine.timeLabel($0) } ?? "\(count)/\(times.count)"
        case .interval:
            guard let n = daysUntilDue(), let end = dueEnd else { return "" }
            if n > 0 { return "D-\(n)" }
            let late = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: end).day ?? 0
            if late >= 0 { return weekendOnly ? String(localized: "이번 주말") : "D-day" }
            return String(localized: "+\(-late)일")
        case .weekly:
            return "\(parts.count - remainingParts(inWeekOf: .now).count)/\(parts.count)"
        case .monthly:
            return Routine.format(monthTotal(of: .now)) + "/" + Routine.format(targetValue) + targetUnit.localizedValue
        case .once:
            return eventLabel(relative: true)
        }
    }

    /// 탭 한 번으로 켜고 끄는 루틴 (양·부위를 적거나 자동 기록되는 건 제외)
    var isSimpleCheck: Bool {
        switch kind {
        case .daily: category != .study && category != .screen && category != .diet
        case .interval: true
        default: false
        }
    }

    /// 목록 한 줄 요약 (주간형은 다음 차례 부위)
    func listStatus(on day: Date) -> String {
        if isRestDay(day) && !isDone(on: day) { return String(localized: "쉬는 날") }
        switch kind {
        case .weekly:
            guard let next = remainingParts(inWeekOf: day).first else { return String(localized: "이번 주 완료") }
            return String(localized: "\(next.localizedValue) 차례 · \(parts.count - remainingParts(inWeekOf: day).count)/\(parts.count)")
        case .monthly:
            return String(localized: "이번 달 \(statusLabel)")
        case .daily where !cal.isDateInToday(day):
            if category == .study { return studyProgress(on: day) }
            return times.count > 1 ? "\(logCount(on: day))/\(times.count)" : Routine.timeLabel(times[0])
        case .interval where !cal.isDateInToday(day):
            // 다른 날을 볼 때는 오늘 기준 D-n 대신 그날의 의미로
            return isDone(on: day) ? String(localized: "완료") : isWithinDueWindow(day) ? (weekendOnly ? String(localized: "주말 예정") : String(localized: "예정일")) : statusLabel
        case .daily where category == .study:
            return Routine.format(dayTotal(on: day)) + "/" + Routine.format(studyGoal) + studyUnit.localizedValue
        default:
            return statusLabel
        }
    }

    /// 위젯처럼 좁은 곳에 쓰는 짧은 상태
    var shortStatus: String {
        switch kind {
        case .daily:
            if category == .diet { return dietPhase().eating ? String(localized: "식사") : String(localized: "금식") }
            if category == .study { return Routine.format(dayTotal(on: .now)) + "/" + Routine.format(studyGoal) }
            if category == .screen { return ScreenTimeShared.status(on: .now) == .exceeded ? String(localized: "초과") : ScreenTimeShared.label(minutes: goalMinutes) }
            return times.count > 1 ? "\(min(logCount(on: .now), times.count))/\(times.count)" : statusLabel
        case .monthly:
            return Routine.format(monthTotal(of: .now)) + targetUnit.localizedValue
        default:
            return statusLabel
        }
    }

    var scheduleLabel: String {
        switch kind {
        case .daily:
            category == .study ? String(localized: "하루 \(Routine.format(studyGoal))\(studyUnit.localizedValue)") + (examLabel.map { String(localized: " · 시험 \($0)") } ?? "")
                : category == .diet ? windowLabel + " · " + statusLabel
                : category == .screen ? String(localized: "하루 \(ScreenTimeShared.label(minutes: goalMinutes))") + (ScreenTimeShared.status(on: .now) == .normal ? "" : " · " + statusLabel)
                : String(localized: "매일 \(statusLabel)")
        case .interval: String(localized: "\(intervalValue)\(intervalUnit.label)마다") + (weekendOnly ? String(localized: " 주말") : "") + " · " + statusLabel
        case .weekly: String(localized: "이번 주 \(statusLabel)")
        case .monthly: String(localized: "이번 달 \(statusLabel)")
        case .once: eventLabel(relative: false) + (location.isEmpty ? "" : " · " + location)
        }
    }
}

// MARK: - 연속 기록 (너그럽게)

extension Routine {
    /// 매일형 연속 기록. 쉬는 날은 건너뛰고, 한 주에 한 번 놓친 날은 봐준다.
    var streak: Int {
        guard kind == .daily else { return 0 }
        var count = 0
        var forgiven: Set<Int> = []
        var day = cal.startOfDay(for: .now)
        // 오늘은 아직 안 했어도 끊긴 걸로 보지 않는다
        if !isSettled(on: day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        while day >= startDay {
            if isDone(on: day) {
                count += 1
            } else if !isRestDay(day) {
                let week = Routine.weekCalendar.component(.weekOfYear, from: day)
                if forgiven.contains(week) { break }
                forgiven.insert(week)
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    /// 이번 주 해야 했던 날 중 한 날 (예: 5/6)
    var weekScore: (done: Int, due: Int)? {
        guard kind == .daily, let start = Routine.weekCalendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return nil }
        let today = cal.startOfDay(for: .now)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            .filter { $0 <= today && $0 >= startDay && !isRestDay($0) }
        guard !days.isEmpty else { return nil }
        return (days.filter { isDone(on: $0) }.count, days.count)
    }
}

// MARK: - 필수 루틴 경고

extension Routine {
    /// 필수 루틴만: 기한이 임박하면 soon, 놓쳤으면 overdue
    func urgency(now: Date = .now) -> Urgency {
        if category == .screen {
            // 폰 사용은 필수 여부와 관계없이 초과하면 알린다
            switch ScreenTimeShared.status(on: now) {
            case .exceeded: return .overdue
            case .warning: return .soon
            case .normal: return .none
            }
        }
        guard isCritical, category != .diet, !isRestDay(now) else { return .none }
        let today = cal.startOfDay(for: now)
        if category == .study {
            guard !isDone(on: today),
                  let remind = cal.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: today) else { return .none }
            if now >= remind { return .overdue }
            return now >= remind.addingTimeInterval(-3600) ? .soon : .none
        }
        switch kind {
        case .monthly:
            return .none
        case .once:
            // 한 시간 안으로 다가온 약속만
            guard !isDone(on: eventDate), !allDay else { return .none }
            let left = eventDate.timeIntervalSince(now)
            return left > 0 && left <= 3600 ? .soon : .none
        case .daily:
            guard now >= startDay, let next = nextTime(on: today),
                  let remind = cal.date(bySettingHour: next / 60, minute: next % 60, second: 0, of: today) else { return .none }
            if now >= remind { return .overdue }
            return now >= remind.addingTimeInterval(-3600) ? .soon : .none
        case .interval:
            guard let end = dueEnd, let n = daysUntilDue(from: now) else { return .none }
            if today > end { return .overdue }
            return n <= 1 ? .soon : .none
        case .weekly:
            let remaining = remainingParts(inWeekOf: today).count
            guard remaining > 0, !isDone(on: today),
                  let weekEnd = Routine.weekCalendar.dateInterval(of: .weekOfYear, for: today)?.end else { return .none }
            let daysLeft = cal.dateComponents([.day], from: today, to: weekEnd).day ?? 0
            if remaining >= daysLeft { return .overdue }
            return remaining == daysLeft - 1 ? .soon : .none
        }
    }
}

// MARK: - 약속

extension Routine {
    var eventTimeLabel: String {
        allDay ? String(localized: "하루 종일") : eventDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// relative: 오늘·내일·D-n 으로, 아니면 날짜로
    func eventLabel(relative: Bool) -> String {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: eventDate)).day ?? 0
        let c = cal.dateComponents([.month, .day], from: eventDate)
        let weekday = eventDate.formatted(.dateTime.weekday(.abbreviated).locale(.app))
        let date = String(localized: "\(c.month ?? 0)월 \(c.day ?? 0)일 (\(weekday))")
        guard relative else { return date + " " + eventTimeLabel }
        switch days {
        case 0: return allDay ? String(localized: "오늘") : eventTimeLabel
        case 1: return String(localized: "내일 \(eventTimeLabel)")
        case 2...: return "D-\(days)"
        default: return String(localized: "지남")
        }
    }

    /// 아직 안 지난 약속
    var isUpcoming: Bool {
        kind == .once && cal.startOfDay(for: eventDate) >= cal.startOfDay(for: .now)
    }
}

// MARK: - 자격증 공부

extension Routine {
    func studyProgress(on day: Date) -> String {
        Routine.format(dayTotal(on: day)) + "/" + Routine.format(studyGoal) + studyUnit.localizedValue
    }

    /// 시험까지 남은 날 (지났으면 nil)
    var examDaysLeft: Int? {
        guard let examDate else { return nil }
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: examDate)).day ?? 0
        return n >= 0 ? n : nil
    }

    var examLabel: String? {
        examDaysLeft.map { $0 == 0 ? "D-day" : "D-\($0)" }
    }

    var studyTimeLabel: String {
        Routine.timeLabel(studyStart) + "–" + Routine.timeLabel(studyEnd)
    }

    /// 지금이 같이 공부하기로 한 시간인지
    func isStudyTime(_ now: Date = .now) -> Bool {
        guard studyTogether else { return false }
        let c = cal.dateComponents([.hour, .minute], from: now)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return m >= studyStart && m < studyEnd
    }
}

// MARK: - 월간형

extension Routine {
    /// 이번 달 누적. 값이 없는 기록은 1회로 센다.
    func monthTotal(of day: Date) -> Double {
        guard let month = cal.dateInterval(of: .month, for: day) else { return 0 }
        return activeLogs.filter { month.containsHalfOpen($0.date) }.reduce(0) { $0 + ($1.value ?? 1) }
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - 주간형 (월요일 시작)

extension Routine {
    static var weekCalendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    func logs(inWeekOf day: Date) -> [RoutineLog] {
        guard let week = Routine.weekCalendar.dateInterval(of: .weekOfYear, for: day) else { return [] }
        return activeLogs.filter { week.containsHalfOpen($0.date) }
    }

    func doneParts(inWeekOf day: Date) -> Set<String> {
        Set(logs(inWeekOf: day).compactMap(\.part))
    }

    /// 아직 안 한 항목. 정해 둔 순서를 유지하므로 첫 번째가 다음 추천.
    func remainingParts(inWeekOf day: Date) -> [String] {
        let done = doneParts(inWeekOf: day)
        return parts.filter { !done.contains($0) }
    }

    func weekRate(of day: Date) -> Double? {
        guard !parts.isEmpty else { return nil }
        return Double(parts.count - remainingParts(inWeekOf: day).count) / Double(parts.count)
    }

    func part(loggedOn day: Date) -> [String] {
        (logs ?? []).filter { cal.isDate($0.date, inSameDayAs: day) }.compactMap(\.part)
    }
}

extension Array where Element == Routine {
    /// 그날 해야 했던 루틴 중 끝낸 비율. 기록할 대상이 없으면 nil.
    /// 주간형은 쉬는 날이 있어도 되므로 한 날만 센다.
    func completion(on day: Date, today: Date = .now) -> Double? {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        let t = cal.startOfDay(for: today)
        guard d <= t else { return nil }
        let expected = filter { r in
            r.isDone(on: d)
                || (r.kind == .daily && d >= r.startDay && !r.isRestDay(d) && !(r.category == .screen && d == t))
                || (d == t && r.kind == .interval && r.appears(on: d, today: today))
        }
        guard !expected.isEmpty else { return nil }
        return Double(expected.filter { $0.isDone(on: d) }.count) / Double(expected.count)
    }
}

extension DateInterval {
    /// DateInterval.contains 는 끝 시각도 포함해서, 다음 주·다음 달 자정 기록이 섞여 들어온다
    func containsHalfOpen(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

extension Calendar {
    func days(endingAt end: Date, count: Int) -> [Date] {
        let last = startOfDay(for: end)
        return (0..<count).reversed().compactMap { date(byAdding: .day, value: -$0, to: last) }
    }
}
