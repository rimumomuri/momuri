import AppIntents
import SwiftData

/// Siri·단축어·제어 센터에서 고르는 루틴
struct RoutineEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "루틴"
    static let defaultQuery = RoutineQuery()

    let id: String
    let name: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ routine: Routine) {
        id = routine.id.uuidString
        name = routine.displayName
        symbol = routine.category.symbol
    }
}

struct RoutineQuery: EntityStringQuery {
    @MainActor
    private func all() -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.sortOrder)])
        return ((try? SharedStore.container.mainContext.fetch(descriptor)) ?? []).filter { $0.kind != .once }
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [RoutineEntity] {
        all().filter { identifiers.contains($0.id.uuidString) }.map(RoutineEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RoutineEntity] {
        let key = string.replacingOccurrences(of: " ", with: "")
        // 추천 이름은 한국어로 저장되므로 화면 이름(번역)으로도 찾는다
        return all().filter { r in
            [r.name, r.displayName].contains { $0.replacingOccurrences(of: " ", with: "").contains(key) }
        }.map(RoutineEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RoutineEntity] {
        all().map(RoutineEntity.init)
    }
}

@MainActor
private func routine(for entity: RoutineEntity) -> Routine? {
    let all = (try? SharedStore.container.mainContext.fetch(FetchDescriptor<Routine>())) ?? []
    return all.first { $0.id.uuidString == entity.id }
}

/// "momuri에 약 기록" — 앱을 열지 않고 기록
struct LogRoutineIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "루틴 기록하기"
    static let description = IntentDescription("루틴을 했다고 기록해요. 러닝·공부는 양도 함께 적을 수 있어요.")

    @Parameter(title: "루틴")
    var routine: RoutineEntity

    @Parameter(title: "양 (km, 문제 수 등)")
    var amount: Double?

    init() {}

    init(routine: RoutineEntity) {
        self.routine = routine
    }

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$routine) 기록하기") { \.$amount }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let target = momuriRoutine(for: routine) else {
            return .result(dialog: "루틴을 찾지 못했어요.")
        }
        let message = RoutineActions.quickLog(target, amount: amount, in: SharedStore.container.mainContext)
        return .result(dialog: "\(message)")
    }
}

/// "momuri 오늘 남은 일"
struct TodaySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "오늘 남은 일"
    static let description = IntentDescription("오늘 아직 안 한 루틴과 약속을 알려줘요.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let all = (try? SharedStore.container.mainContext.fetch(FetchDescriptor<Routine>())) ?? []
        let due = all.filter { $0.appears(on: .now) && !$0.isDone(on: .now) }
        guard !due.isEmpty else { return .result(dialog: "오늘 할 일을 다 했어요.") }
        let list = due.prefix(5).map { "\($0.displayName) \($0.listStatus(on: .now))" }.joined(separator: ", ")
        return .result(dialog: "남은 일 \(due.count)개: \(list)")
    }
}

@MainActor
func momuriRoutine(for entity: RoutineEntity) -> Routine? {
    routine(for: entity)
}
