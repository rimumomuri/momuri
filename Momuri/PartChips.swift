import SwiftUI

/// 주간형 항목(부위) 칩 줄. onTap 이 없으면 읽기 전용.
struct PartChips: View {
    let routine: Routine
    let day: Date
    var compact = false
    var onTap: ((String) -> Void)?

    var body: some View {
        let doneOnDay = Set(routine.part(loggedOn: day))
        let doneInWeek = routine.doneParts(inWeekOf: day)
        let next = routine.remainingParts(inWeekOf: day).first

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(routine.parts, id: \.self) { part in
                    let state: ChipState = doneOnDay.contains(part) ? .doneToday
                        : doneInWeek.contains(part) ? .doneEarlier
                        : part == next ? .next : .todo
                    Button { onTap?(part) } label: { chip(part.localizedValue, state) }
                        .buttonStyle(.plain)
                        .disabled(onTap == nil || state == .doneEarlier)
                }
            }
        }
    }

    private enum ChipState { case doneToday, doneEarlier, next, todo }

    private func chip(_ text: String, _ state: ChipState) -> some View {
        let filled = state == .doneToday || state == .doneEarlier
        return Text(text)
            .font(compact ? .caption2 : .footnote.weight(.medium))
            .foregroundStyle(state == .doneToday ? Color(.systemBackground) : state == .doneEarlier ? Color.secondary : Color.primary)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 3 : 6)
            .background(Capsule().fill(Color.primary.opacity(state == .doneToday ? 1 : state == .doneEarlier ? 0.1 : 0)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(filled ? 0 : state == .next ? 0.9 : 0.2),
                                            lineWidth: state == .next ? 1.2 : 1))
    }
}
