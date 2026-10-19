import Foundation
import SwiftData

/// AI를 못 쓰는 기기(또는 AI가 실패했을 때)를 위한 규칙 기반 해석.
/// 자주 쓰는 말만 처리한다: 기록, 질문, 매일·주기 루틴, 약속.
@MainActor
enum ChatFallback {
    enum Result {
        case reply(String)
        case draft(RoutineFactory.Draft, String)
    }

    static func handle(_ text: String, now: Date = .now) -> Result {
        let t = text.replacingOccurrences(of: "  ", with: " ")
        if isQuestion(t) { return .reply(answer(t)) }
        if isDoneStatement(t) {
            if isNegative(t) { return .reply(String(localized: "알겠어요. 기록하지 않았어요.")) }
            if let reply = log(t, now: now) { return .reply(reply) }
        }
        if let draft = appointment(t, now: now) { return .draft(draft, String(localized: "약속으로 만들까요?")) }
        if let draft = routine(t) { return .draft(draft, String(localized: "이렇게 만들까요?")) }
        return .reply(String(localized: "이해하지 못했어요. 예: '약 먹었어', '매일 아침 8시 비타민', '다음 주 금요일 7시 저녁 약속', '이번 달 러닝 얼마나 했어?'"))
    }

    // MARK: - 질문

    private static func isQuestion(_ t: String) -> Bool {
        if t.contains("매일") || intervalOf(t) != nil { return false }
        return t.contains("?") || ["얼마나", "몇 ", "몇번", "몇 번", "언제"].contains { t.contains($0) }
    }

    private static func isDoneStatement(_ t: String) -> Bool {
        ["했어", "했다", "했음", "먹었", "뛰었", "풀었", "끝냈", "완료", "다녀왔", "갔다 왔"].contains { t.contains($0) }
    }

    private static func isNegative(_ t: String) -> Bool {
        ["안 ", "못 ", "않", "안했", "못했"].contains { t.contains($0) }
    }

    private static func answer(_ t: String) -> String {
        let all = routines()
        let period = t.contains("주") && !t.contains("주기") ? "이번 주" : t.contains("달") || t.contains("월") ? "이번 달" : "최근 30일"
        guard let routine = match(t, in: all) else {
            return all.isEmpty ? String(localized: "아직 루틴이 없어요.") : String(localized: "어떤 루틴이 궁금한지 이름을 넣어 주세요. 예: 이번 달 러닝 얼마나 했어?")
        }
        if t.contains("언제"), routine.kind == .interval || routine.kind == .once {
            return String(localized: "\(routine.displayName)은 \(routine.scheduleLabel)이에요.")
        }
        let cal = Calendar.current
        let start: Date = period == "이번 주"
            ? (Routine.weekCalendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now)
            : period == "이번 달" ? (cal.dateInterval(of: .month, for: .now)?.start ?? .now)
            : (cal.date(byAdding: .day, value: -30, to: .now) ?? .now)
        let logs = (routine.logs ?? []).filter { $0.date >= start && !$0.skipped }
        let days = Set(logs.map { cal.startOfDay(for: $0.date) }).count
        let total = logs.reduce(0) { $0 + ($1.value ?? 0) }
        let unit = routine.category == .study ? routine.studyUnit : routine.targetUnit
        // period 는 비교용 한국어 값, 화면에는 번역해서 보여 준다
        let periodLabel = period == "이번 주" ? String(localized: "이번 주") : period == "이번 달" ? String(localized: "이번 달") : String(localized: "최근 30일")
        return total > 0
            ? String(localized: "\(routine.displayName): \(periodLabel) \(days)일 했어요, 합계 \(Routine.format(total))\(unit.localizedValue). 지금 \(routine.statusLabel)")
            : String(localized: "\(routine.displayName): \(periodLabel) \(days)일 했어요. 지금 \(routine.statusLabel)")
    }

    // MARK: - 기록

    private static func log(_ t: String, now: Date) -> String? {
        guard let routine = match(t, in: routines()) else { return nil }
        let context = SharedStore.container.mainContext
        let day = t.contains("어제") ? Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now : now
        let part = routine.parts.first { t.contains($0) }
        return RoutineActions.quickLog(routine, amount: number(in: t), part: part, on: day, in: context)
    }

    // MARK: - 만들기

    private static func routine(_ t: String) -> RoutineFactory.Draft? {
        let interval = intervalOf(t)
        guard t.contains("매일") || interval != nil else { return nil }
        let name = cleanName(t)
        guard !name.isEmpty else { return nil }
        let category: RoutineCategory =
            ["약", "비타민", "영양제", "유산균"].contains { name.contains($0) } ? .medicine
            : ["샴푸", "강아지", "발톱", "심장사상충", "구충"].contains { name.contains($0) } ? .pet
            : ["제모", "미용실", "피부과", "네일"].contains { name.contains($0) } ? .care
            : .other
        return RoutineFactory.Draft(
            name: name,
            category: category,
            intervalValue: interval?.value,
            intervalUnit: interval?.unit,
            time: timeOf(t)
        )
    }

    private static func appointment(_ t: String, now: Date) -> RoutineFactory.Draft? {
        let repeating = ["매일", "매주", "매달", "격주", "마다", "에 한 번", "에 한번"].contains { t.contains($0) }
        guard !repeating, let date = dateOf(t, now: now) else { return nil }
        var location = ""
        if let range = t.range(of: "에서") {
            location = t[..<range.lowerBound].split(separator: " ").last.map(String.init) ?? ""
        }
        var name = cleanName(t)
        if !location.isEmpty { name = name.replacingOccurrences(of: location + "에서", with: "").trimmingCharacters(in: .whitespaces) }
        return RoutineFactory.Draft(name: name.isEmpty ? "약속" : name, category: .appointment, time: timeOf(t, assumePM: true), date: date, location: location)
    }

    // MARK: - 조각 해석

    private static func intervalOf(_ t: String) -> (value: Int, unit: IntervalUnit)? {
        if t.contains("한 달에 한") || t.contains("한달에 한") || t.contains("매달") { return (1, .month) }
        if t.contains("일주일에 한") || t.contains("매주") { return (1, .week) }
        let patterns: [(String, IntervalUnit)] = [("개월", .month), ("달", .month), ("주", .week), ("일", .day)]
        for (word, unit) in patterns {
            if let r = t.range(of: "(\\d+)\\s*\(word)\\s*(마다|에 한)", options: .regularExpression) {
                return (Int(t[r].prefix { $0.isNumber }) ?? 1, unit)
            }
        }
        if t.contains("두 달") || t.contains("두달") { return (2, .month) }
        if t.contains("2주") || t.contains("격주") { return (2, .week) }
        return nil
    }

    private static func timeOf(_ t: String, assumePM: Bool = false) -> (hour: Int, minute: Int)? {
        guard let r = t.range(of: "(\\d{1,2})\\s*시(?!간)(\\s*(\\d{1,2})\\s*분|\\s*반)?", options: .regularExpression) else {
            if let r = t.range(of: "(\\d{1,2}):(\\d{2})", options: .regularExpression) { return ChatParse.time(String(t[r])) }
            return nil
        }
        let s = String(t[r])
        let nums = s.split { !$0.isNumber }.compactMap { Int($0) }
        var hour = nums.first ?? 9
        let minute = s.contains("반") ? 30 : nums.count > 1 ? nums[1] : 0
        let pm = t.contains("오후") || t.contains("저녁") || t.contains("밤")
        let am = t.contains("오전") || t.contains("아침") || t.contains("새벽")
        if pm && hour < 12 { hour += 12 }
        if (t.contains("밤") || t.contains("자정")) && hour == 12 { hour = 0 }
        // 오전·오후를 말하지 않은 1~7시는 보통 오후 (점심 1시, 3시 회의)
        if assumePM && !pm && !am && (1...7).contains(hour) { hour += 12 }
        return (hour % 24, minute)
    }

    private static func dateOf(_ t: String, now: Date) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        if t.contains("모레") { return cal.date(byAdding: .day, value: 2, to: today) }
        if t.contains("내일") { return cal.date(byAdding: .day, value: 1, to: today) }
        if t.contains("오늘") && timeOf(t) != nil { return today }
        if let r = t.range(of: "(\\d{1,2})\\s*월\\s*(\\d{1,2})\\s*일", options: .regularExpression) {
            let nums = t[r].split { !$0.isNumber }.compactMap { Int($0) }
            var c = cal.dateComponents([.year], from: today)
            c.month = nums[0]
            c.day = nums[1]
            guard let d = cal.date(from: c) else { return nil }
            return d < today ? cal.date(byAdding: .year, value: 1, to: d) : d
        }
        let days = ["일요일": 1, "월요일": 2, "화요일": 3, "수요일": 4, "목요일": 5, "금요일": 6, "토요일": 7]
        if let (_, weekday) = days.first(where: { t.contains($0.key) }) {
            var next = cal.nextDate(after: today, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime) ?? today
            if t.contains("다음 주") || t.contains("다음주") {
                let thisWeek = Routine.weekCalendar.dateInterval(of: .weekOfYear, for: today)
                if let end = thisWeek?.end, next < end { next = cal.date(byAdding: .day, value: 7, to: next) ?? next }
            }
            return next
        }
        return nil
    }

    private static func number(in t: String) -> Double? {
        guard let r = t.range(of: "\\d+(\\.\\d+)?", options: .regularExpression) else { return nil }
        return Double(t[r])
    }

    /// 시간·날짜·주기 표현을 빼고 남은 말을 이름으로
    private static func cleanName(_ t: String) -> String {
        var s = t
        let patterns = [
            "(아침|점심|저녁|밤|오전|오후|새벽)(에)?\\s*(?=\\d)", "(아침|점심|저녁|밤|새벽)에\\s",
            "\\d{1,2}\\s*월\\s*\\d{1,2}\\s*일", "\\d{1,2}\\s*시(\\s*\\d{1,2}\\s*분|\\s*반)?", "\\d{1,2}:\\d{2}",
            "\\d+\\s*(개월|달|주|일)\\s*(마다|에 한 번|에 한번)", "(한 ?달|일주일|두 ?달)에 한 ?번",
            "(다음 ?주|이번 ?주)", "(일|월|화|수|목|금|토)요일", "매일|매주|매달|격주|오늘|내일|모레",
            "(아침|점심|저녁|밤|오전|오후|새벽)(에)?\\s*(?=\\d)", "(먹기|하기|가기|만들어줘|만들어 줘|추가해줘|추가|해줘|알려줘)$",
        ]
        for p in patterns { s = s.replacingOccurrences(of: p, with: " ", options: .regularExpression) }
        s = s.replacingOccurrences(of: "\\s*(에|에는|은|는)\\s+", with: " ", options: .regularExpression)
        return s.split(separator: " ").joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.에"))
    }

    private static func routines() -> [Routine] {
        (try? SharedStore.container.mainContext.fetch(FetchDescriptor<Routine>())) ?? []
    }

    /// 문장에 이름이 들어 있는 루틴 (긴 이름 우선)
    private static func match(_ t: String, in all: [Routine]) -> Routine? {
        let key = t.replacingOccurrences(of: " ", with: "")
        let named = all.filter { !$0.name.isEmpty && $0.kind != .once }
        if let hit = named.sorted(by: { $0.name.count > $1.name.count })
            .first(where: { key.contains($0.name.replacingOccurrences(of: " ", with: "")) }) {
            return hit
        }
        // 이름이 없으면 분류 이름의 낱말로 (약속은 제외, "약속"이 "약"에 걸리지 않게)
        guard !key.contains("약속") else { return nil }
        return named.sorted { $0.sortOrder < $1.sortOrder }.first { r in
            r.category.title.split(separator: "·").map { $0.replacingOccurrences(of: " ", with: "") }.contains { !$0.isEmpty && key.contains($0) }
        }
    }
}
