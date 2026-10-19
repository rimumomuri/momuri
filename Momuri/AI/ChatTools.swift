import Foundation
import FoundationModels
import SwiftData

// AI가 부르는 앱 기능들. 바꾸는 일은 메인 스레드에서 SwiftData로 한다.

@Generable
enum DraftCategory {
    case medicine, gym, cardio, care, pet, study, diet, other

    var category: RoutineCategory {
        switch self {
        case .medicine: .medicine
        case .gym: .gym
        case .cardio: .cardio
        case .care: .care
        case .pet: .pet
        case .study: .study
        case .diet: .diet
        case .other: .other
        }
    }
}

@Generable
enum DraftUnit {
    case day, week, month

    var unit: IntervalUnit {
        switch self {
        case .day: .day
        case .week: .week
        case .month: .month
        }
    }
}

enum ChatParse {
    static func time(_ raw: String?) -> (hour: Int, minute: Int)? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        guard let h = parts.first, (0..<24).contains(h) else { return nil }
        return (h, parts.count > 1 ? min(max(parts[1], 0), 59) : 0)
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }

    /// 이름이 정확하지 않아도 가장 비슷한 루틴을 찾는다
    @MainActor
    static func routine(named name: String) -> Routine? {
        let all = (try? SharedStore.container.mainContext.fetch(FetchDescriptor<Routine>())) ?? []
        func norm(_ s: String) -> String { s.replacingOccurrences(of: " ", with: "").lowercased() }
        let key = norm(name)
        guard !key.isEmpty else { return nil }
        let named = all.filter { !$0.name.isEmpty && $0.kind != .once }.sorted { $0.sortOrder < $1.sortOrder }
        // 추천 이름은 한국어로 저장되므로 화면 이름(번역)으로도 찾는다
        func names(_ r: Routine) -> [String] { [norm(r.name), norm(r.displayName)] }
        return named.first { names($0).contains(key) }
            ?? named.first { names($0).contains { $0.contains(key) || key.contains($0) } }
            ?? named.first { $0.category.title.split(separator: "·").map { norm(String($0)) }.contains(key) }
    }
}

struct ProposeRoutineTool: Tool {
    let chat: ChatModel
    let name = "proposeRoutine"
    let description = "사용자가 새로 반복할 루틴을 만들고 싶어할 때 확인 카드를 띄운다. 약속(한 번뿐인 일정)은 proposeAppointment를 쓴다."

    @Generable
    struct Arguments {
        @Guide(description: "짧은 루틴 이름. 예: 비타민D, 수염 제모, 헬스, 정보처리기사")
        var name: String
        @Guide(description: "분류. 약·영양제=medicine, 헬스=gym, 러닝=cardio, 제모·미용실=care, 강아지=pet, 자격증·시험 공부=study, 식단=diet, 그 외=other")
        var category: DraftCategory
        @Guide(description: "주기적인 일의 주기 숫자. 한 달에 한 번이면 1, 2주마다면 2")
        var intervalValue: Int?
        @Guide(description: "주기 단위")
        var intervalUnit: DraftUnit?
        @Guide(description: "알림 시각 HH:mm (24시간). 예: 08:00, 21:30")
        var time: String?
        @Guide(description: "헬스 부위들. 예: 가슴, 등, 하체, 어깨")
        var parts: [String]?
        @Guide(description: "목표 숫자. 공부는 하루 문제 수, 러닝은 한 달 km")
        var goal: Double?
        @Guide(description: "자격증 시험일 yyyy-MM-dd")
        var examDate: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        let draft = RoutineFactory.Draft(
            name: a.name,
            category: a.category.category,
            intervalValue: a.intervalValue,
            intervalUnit: a.intervalUnit?.unit,
            time: ChatParse.time(a.time),
            parts: a.parts ?? [],
            goal: a.goal,
            date: ChatParse.date(a.examDate)
        )
        await chat.addDraft(draft)
        return "확인 카드를 보여줬어요. 사용자가 [추가]를 누르면 만들어져요."
    }
}

struct ProposeAppointmentTool: Tool {
    let chat: ChatModel
    let name = "proposeAppointment"
    let description = "날짜가 정해진 한 번뿐인 약속·일정을 만들 때 확인 카드를 띄운다."

    @Generable
    struct Arguments {
        @Guide(description: "약속 제목. 예: 유진이랑 저녁, 치과")
        var title: String
        @Guide(description: "날짜 yyyy-MM-dd")
        var date: String
        @Guide(description: "시각 HH:mm (24시간). 모르면 비워 둔다")
        var time: String?
        @Guide(description: "장소. 모르면 비워 둔다")
        var location: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        let draft = RoutineFactory.Draft(
            name: a.title,
            category: .appointment,
            time: ChatParse.time(a.time),
            date: ChatParse.date(a.date) ?? .now,
            location: a.location ?? ""
        )
        await chat.addDraft(draft)
        return "확인 카드를 보여줬어요."
    }
}

struct LogRoutineTool: Tool {
    let name = "logRoutine"
    let description = "사용자가 루틴을 했다고 말하면 기록한다. 예: 약 먹었어, 5km 뛰었어, 헬스 가슴 했어, 20문제 풀었어"

    @Generable
    struct Arguments {
        @Guide(description: "기록할 루틴 이름 (현재 루틴 목록에서 고른다)")
        var routineName: String
        @Guide(description: "양. 러닝 km, 공부 문제 수 등. 없으면 비워 둔다")
        var amount: Double?
        @Guide(description: "헬스 부위. 예: 가슴")
        var part: String?
        @Guide(description: "며칠 전인지. 오늘 0, 어제 1")
        var daysAgo: Int?
    }

    func call(arguments a: Arguments) async throws -> String {
        await MainActor.run {
            guard let routine = ChatParse.routine(named: a.routineName) else {
                return "'\(a.routineName)' 루틴을 찾지 못했어요."
            }
            let day = Calendar.current.date(byAdding: .day, value: -(a.daysAgo ?? 0), to: .now) ?? .now
            return RoutineActions.quickLog(routine, amount: a.amount, part: a.part, on: day, in: SharedStore.container.mainContext)
        }
    }
}

struct StatsTool: Tool {
    let name = "getStats"
    let description = "루틴 기록을 조회한다. 질문에 답하기 전에 꼭 써서 실제 숫자로 답한다."

    @Generable
    struct Arguments {
        @Guide(description: "궁금한 루틴 이름. 전체가 궁금하면 '전체'")
        var routineName: String
        @Guide(description: "기간: 이번 주, 이번 달, 최근 30일 중 하나")
        var period: String
    }

    func call(arguments a: Arguments) async throws -> String {
        await MainActor.run {
            let cal = Calendar.current
            let now = Date.now
            let start: Date = a.period.contains("주")
                ? (Routine.weekCalendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now)
                : a.period.contains("달")
                    ? (cal.dateInterval(of: .month, for: now)?.start ?? now)
                    : (cal.date(byAdding: .day, value: -30, to: now) ?? now)
            let all = (try? SharedStore.container.mainContext.fetch(FetchDescriptor<Routine>())) ?? []
            let targets = a.routineName.contains("전체") ? all : ChatParse.routine(named: a.routineName).map { [$0] } ?? []
            guard !targets.isEmpty else { return "'\(a.routineName)' 루틴을 찾지 못했어요." }
            return targets.prefix(10).map { r in
                let logs = (r.logs ?? []).filter { $0.date >= start && !$0.skipped }
                let days = Set(logs.map { cal.startOfDay(for: $0.date) }).count
                var line = "\(r.displayName): \(a.period) \(days)일 기록"
                let total = logs.reduce(0) { $0 + ($1.value ?? 0) }
                if total > 0 { line += ", 합계 \(Routine.format(total))\(r.category == .study ? r.studyUnit : r.targetUnit)" }
                if r.kind == .weekly { line += ", 부위 " + logs.compactMap(\.part).joined(separator: "·") }
                line += ", 지금 상태 \(r.statusLabel)"
                return line
            }.joined(separator: "\n")
        }
    }
}
