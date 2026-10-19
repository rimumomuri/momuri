import SwiftUI

/// 홈: 오늘 루틴을 가운데 모무리쿤에 액체 줄기로 이어진 카드로 보여준다 (그리기·움직임은 RoutineOrbitView).
/// 색은 상태만 말한다: 검정=할 일, 회색+체크=끝냄, 주황=곧, 빨강=기한 지남·긴급.
/// 요즘 자주 놓치는 루틴은 카드에 빨간 점, 아래에 한 줄로 알려 준다.
struct HomeBlobView: View {
    let routines: [Routine]
    let onOpen: (Routine) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cal = Calendar.current

    // MARK: - 방울 데이터

    enum Tone {
        case todo, done, soon, missed, rest

        var fill: Color {
            switch self {
            case .todo: Color(.label)
            case .done: Color(.systemGray4)
            case .soon: Color(.systemOrange)
            case .missed: Color(.systemRed)
            case .rest: Color(.systemGray5)
            }
        }

        var text: Color {
            switch self {
            case .done, .rest: Color(.secondaryLabel)
            default: Color(.systemBackground)
            }
        }
    }

    struct Blob: Identifiable {
        static let corner: CGFloat = 20

        let id: UUID
        let routine: Routine
        let title: String
        let status: String
        let tone: Tone
        let oftenMissed: Bool
        let size: CGSize
        let drift: OrbitDrift

        var accessibilityText: String {
            let state: String = switch tone {
            case .todo: String(localized: "할 일")
            case .done: String(localized: "끝냄")
            case .soon: String(localized: "곧 해야 해요")
            case .missed: String(localized: "기한 지남")
            case .rest: String(localized: "쉬는 날")
            }
            return "\(title), \(status), \(state)" + (oftenMissed ? ", " + String(localized: "요즘 자주 놓쳐요") : "")
        }
    }

    private var blobs: [Blob] {
        let today = Date.now
        let items = routines.filter { r in
            (r.kind != .once && r.appears(on: today)) || (r.kind == .once && r.isUpcoming && (cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: r.eventDate)).day ?? 99) <= 3)
        }
        let missed = Set(oftenMissed.map(\.0))
        return items.prefix(10).map { r in
            let tone = tone(of: r)
            let base = r.isCritical ? CGSize(width: 108, height: 62) : CGSize(width: 100, height: 58)
            let size = tone == .done || tone == .rest ? CGSize(width: base.width * 0.9, height: base.height * 0.9) : base
            return Blob(id: r.id, routine: r, title: r.displayName, status: r.kind == .once ? r.eventLabel(relative: true) : r.listStatus(on: today),
                        tone: tone, oftenMissed: missed.contains(r.displayName), size: size, drift: OrbitDrift(id: r.id))
        }
    }

    private func tone(of r: Routine) -> Tone {
        let today = Date.now
        if r.isRestDay(today) && !r.isDone(on: today) { return .rest }
        if r.isSettled(on: today) && r.kind != .weekly && r.kind != .monthly { return .done }
        switch r.urgency() {
        case .overdue: return .missed
        case .soon: return .soon
        case .none: break
        }
        if let n = r.daysUntilDue(), n < 0 { return .missed }
        return .todo
    }

    /// 요즘 자주 놓치는 루틴 (홈 아래 한 줄)
    private var oftenMissed: [(String, Int, Int)] {
        routines.compactMap { r in
            guard r.kind == .daily, r.category != .screen else { return nil }
            let days = (1...7).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now)) }
                .filter { $0 >= r.startDay && !r.isRestDay($0) }
            let missed = days.filter { !r.isDone(on: $0) }.count
            return days.count >= 3 && Double(missed) / Double(days.count) >= 0.4 ? (r.displayName, missed, days.count) : nil
        }
    }

    private var oftenMissedLine: String {
        let list = oftenMissed.map { String(localized: "\($0.0) (7일 중 \($0.1)번)") }.joined(separator: ", ")
        return String(localized: "요즘 자주 놓쳐요: \(list)")
    }

    private var progress: (done: Int, total: Int) {
        let due = routines.filter { $0.kind != .once && $0.appears(on: .now) && $0.kind != .weekly && $0.kind != .monthly }
        return (due.filter { $0.isSettled(on: .now) }.count, due.count)
    }

    // MARK: - 화면

    var body: some View {
        let blobs = blobs
        VStack(spacing: 12) {
            RoutineOrbitView(blobs: blobs, onOpen: onOpen) {
                character(blobs: blobs)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 470)

            summary
        }
        .padding(.horizontal, 20)
    }

    /// 밤이거나, 할 일이 없고 오늘이 쉬는 날이면 모무리쿤이 쉰다
    private func isResting(_ blobs: [Blob]) -> Bool {
        let hour = cal.component(.hour, from: .now)
        if hour >= 23 || hour < 6 { return true }
        return blobs.isEmpty && routines.contains { $0.isRestDay(.now) }
    }

    private func character(blobs: [Blob]) -> some View {
        let p = progress
        return ZStack {
            Circle().fill(Color(.systemBackground)).frame(width: 116, height: 116)
            // 완료 점프·전부 완료 축하는 모무리쿤이 completed 변화를 보고 스스로 한다
            MomuriKunView(rate: p.total > 0 ? Double(p.done) / Double(p.total) : 0,
                          completed: p.done,
                          isResting: isResting(blobs),
                          isReminding: blobs.contains { $0.tone == .soon })
                .frame(width: 92)
                .offset(y: -8)
                .allowsHitTesting(false)
            if p.total > 0 {
                Text("\(p.done)/\(p.total)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.label)))
                    .foregroundStyle(Color(.systemBackground))
                    .offset(y: 58)
            }
        }
        .accessibilityLabel("오늘 \(p.done)개 끝냄, 전체 \(p.total)개")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if blobs.isEmpty {
                Text(routines.isEmpty ? "오른쪽 위 + 로 첫 루틴을 만들어 보세요" : "오늘은 할 일이 없어요. 푹 쉬어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !oftenMissed.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(Color(.systemRed)).frame(width: 6, height: 6)
                    Text(oftenMissedLine)
                        .font(.footnote)
                }
            }
            Text("카드를 누르면 자세히 볼 수 있어요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
