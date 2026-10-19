import SwiftUI

struct GrassCellView: View {
    let cell: GrassCell

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        switch cell {
        case .done:
            shape.fill(Color.primary.opacity(0.85))
        case .empty:
            shape.fill(Color.primary.opacity(0.07))
        case .rest:
            // 쉬는 날: 실패처럼 보이지 않게 작은 점만
            Circle().fill(Color.primary.opacity(0.25)).padding(3.5)
        case .scheduled:
            shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
        case .today:
            shape.strokeBorder(Color.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
    }
}

extension Urgency {
    /// 무채색 앱에서 유일하게 색을 쓰는 곳
    var color: Color? {
        switch self {
        case .none: nil
        case .soon: .orange
        case .overdue: .red
        }
    }
}

struct GrassRow: View {
    let name: String
    let trailing: String?
    let cells: [GrassCell]
    var urgency: Urgency = .none
    var labelWidth: CGFloat = 52
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            HStack(spacing: spacing) {
                ForEach(cells.indices, id: \.self) { i in
                    GrassCellView(cell: cells[i]).aspectRatio(1, contentMode: .fit)
                }
            }
            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .monospacedDigit()
                    .fontWeight(urgency == .none ? .regular : .semibold)
                    .foregroundStyle(urgency.color ?? .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }
}

struct RoutineSnapshot: Identifiable {
    let id: String
    let name: String
    let status: String
    let cells: [GrassCell]
    let dueToday: Bool
    let doneToday: Bool
    let urgency: Urgency
    let simpleCheck: Bool

    init(_ routine: Routine, days: Int, today: Date = .now) {
        id = routine.id.uuidString
        name = routine.displayName
        status = routine.shortStatus
        cells = Calendar.current.days(endingAt: today, count: days).map { routine.grassCell(on: $0, today: today) }
        dueToday = routine.appears(on: today, today: today)
        doneToday = routine.isDone(on: today)
        urgency = routine.urgency(now: today)
        simpleCheck = routine.isSimpleCheck
    }
}
