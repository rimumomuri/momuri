import Foundation
import SwiftData

enum RoutineKind: String, Codable, CaseIterable {
    case daily, interval, weekly, monthly
    /// 한 번뿐인 약속·일정
    case once
}

enum IntervalUnit: String, Codable, CaseIterable {
    case day, week, month

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    var label: String {
        switch self {
        case .day: String(localized: "일")
        case .week: String(localized: "주")
        case .month: String(localized: "개월")
        }
    }
}

/// 루틴을 만들 때 고르는 분류. 분류마다 설정 화면과 기본값이 다르다.
enum RoutineCategory: String, Codable, CaseIterable {
    case appointment, study, medicine, gym, cardio, care, pet, diet, screen, other

    var title: String {
        switch self {
        case .appointment: String(localized: "약속·일정")
        case .study: String(localized: "자격증 공부")
        case .medicine: String(localized: "약·영양제")
        case .gym: String(localized: "헬스")
        case .cardio: String(localized: "러닝·유산소")
        case .care: String(localized: "관리·미용")
        case .pet: String(localized: "반려견")
        case .diet: String(localized: "식단")
        case .screen: String(localized: "폰 사용")
        case .other: String(localized: "기타")
        }
    }

    var subtitle: String {
        switch self {
        case .appointment: String(localized: "날짜·시간·장소가 있는 한 번의 일정")
        case .study: String(localized: "시험 D-day와 매일 목표, 같이 공부")
        case .medicine: String(localized: "매일 정해진 시간에 복용")
        case .gym: String(localized: "한 주에 부위 채우기")
        case .cardio: String(localized: "한 달 목표 거리·횟수")
        case .care: String(localized: "제모, 미용실처럼 주기적으로")
        case .pet: String(localized: "샴푸, 심장사상충, 접종")
        case .diet: String(localized: "식사 시간대와 금식")
        case .screen: String(localized: "하루 사용 시간 목표")
        case .other: String(localized: "매일·주기·주간 자유롭게")
        }
    }

    var symbol: String {
        switch self {
        case .appointment: "calendar"
        case .study: "book"
        case .medicine: "pills"
        case .gym: "dumbbell"
        case .cardio: "figure.run"
        case .care: "scissors"
        case .pet: "pawprint"
        case .diet: "fork.knife"
        case .screen: "iphone"
        case .other: "circle.grid.2x2"
        }
    }

    var isAvailable: Bool { true }

    /// 루틴 탭에서 묶어 보여줄 큰 묶음
    var group: String {
        switch self {
        case .medicine, .gym, .cardio, .diet, .screen: "건강"
        case .study: "공부"
        case .care, .pet: "관리 · 반려견"
        case .appointment: "약속"
        case .other: "기타"
        }
    }

    static let groupOrder = ["건강", "공부", "관리 · 반려견", "기타"]

    /// 분류가 정하는 방식. nil 이면 사용자가 고른다.
    var fixedKind: RoutineKind? {
        switch self {
        case .medicine: .daily
        case .gym: .weekly
        case .cardio: .monthly
        case .care: .interval
        case .pet: .interval
        case .appointment: .once
        case .study: .daily
        case .diet: .daily
        case .screen: .daily
        default: nil
        }
    }
}

@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = RoutineKind.daily.rawValue
    var intervalValue: Int = 1
    var intervalUnitRaw: String = IntervalUnit.month.rawValue
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    var remindDaysBefore: Int = 3
    /// 주간형: 한 주에 채울 항목(헬스 부위 등). 순서가 다음 추천 순서.
    var parts: [String] = []
    var showInWidget: Bool = true
    /// 꼭 해야 하는 루틴. 임박하면 주황, 놓치면 빨강으로 표시한다.
    var isCritical: Bool = false
    /// 쉬는 요일 (Calendar weekday 1=일 … 7=토). 이 날은 해야 할 날에서 빠진다.
    var restWeekdays: [Int] = []
    /// 필수 루틴을 알람(무음이어도 울림)으로 알릴지
    var useAlarm: Bool = false
    /// 주기형: 예정일이 평일이면 그 주(월요일 시작) 토·일로 맞춘다
    var weekendOnly: Bool = false
    var categoryRaw: String = RoutineCategory.other.rawValue
    /// 하루 여러 번 체크하는 매일형(약 등)의 시각들. 분 단위. 비어 있으면 reminderHour/Minute 한 번.
    var reminderTimes: [Int] = []
    /// 월간형 목표. 단위는 "km" 또는 "회".
    var targetValue: Double = 0
    var targetUnit: String = "회"
    /// 식단: 식사 시간대(분 단위). 나머지는 금식.
    var windowStart: Int = 12 * 60
    var windowEnd: Int = 20 * 60
    /// 식단: Dynamic Island·잠금화면에 실시간 표시
    var showLive: Bool = true
    /// 러닝: 건강 앱의 러닝 운동을 자동으로 가져온다
    var autoHealth: Bool = false
    /// 폰 사용: 하루 목표(분)
    var goalMinutes: Int = 120
    /// 약속: 날짜와 시각, 장소, 몇 분 전에 알릴지
    var eventDate: Date = Date()
    var allDay: Bool = false
    var location: String = ""
    var remindOffsets: [Int] = [60, 1440]
    /// 공유 루틴: 서버의 공유 ID·초대 코드, 내가 만든 공유인지
    var shareId: String?
    var shareCode: String?
    var shareOwner: Bool = false
    /// 자격증 공부: 시험일, 하루 목표와 단위(문제·분·페이지), 같이 공부 시간, 지금 공부 중이면 시작 시각
    var examDate: Date?
    var studyGoal: Double = 30
    var studyUnit: String = "문제"
    var studyTogether: Bool = false
    var studyStart: Int = 21 * 60
    var studyEnd: Int = 22 * 60
    var studyingSince: Date?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \RoutineLog.routine)
    var logs: [RoutineLog]? = []

    init(name: String, kind: RoutineKind, sortOrder: Int = 0) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
    }

    /// 화면에 보여 줄 이름. 추천·기본 이름은 한국어로 저장하고 여기서 번역한다.
    var displayName: String { name.localizedValue }

    var kind: RoutineKind {
        get { RoutineKind(rawValue: kindRaw) ?? .daily }
        set { kindRaw = newValue.rawValue }
    }

    var category: RoutineCategory {
        get { RoutineCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var intervalUnit: IntervalUnit {
        get { IntervalUnit(rawValue: intervalUnitRaw) ?? .month }
        set { intervalUnitRaw = newValue.rawValue }
    }
}

@Model
final class RoutineLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var value: Double?
    var part: String?
    /// 건강 앱 운동 UUID 등 외부에서 가져온 기록의 ID (중복 방지)
    var externalID: String?
    /// "오늘은 쉬기"로 남긴 기록. 완료로 세지 않고 해야 할 날에서도 뺀다.
    var skipped: Bool = false
    var routine: Routine?
    /// 헬스 부위 기록에 딸린 세트들
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.log)
    var sets: [WorkoutSet]? = []

    init(date: Date, value: Double? = nil, part: String? = nil) {
        self.date = date
        self.value = value
        self.part = part
    }
}

@Model
final class WorkoutSet {
    var id: UUID = UUID()
    var exercise: String = ""
    var weight: Double = 0
    var reps: Int = 0
    var order: Int = 0
    var log: RoutineLog?

    init(exercise: String, weight: Double, reps: Int, order: Int) {
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
        self.order = order
    }
}
