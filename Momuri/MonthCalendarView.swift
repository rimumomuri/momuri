import SwiftUI

struct MonthCalendarView: View {
    @Binding var month: Date
    @Binding var selected: Date
    let routines: [Routine]

    private let cal = Calendar.current
    private let weekdays = [String(localized: "일"), String(localized: "월"), String(localized: "화"), String(localized: "수"),
                            String(localized: "목"), String(localized: "금"), String(localized: "토")]

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(cal.component(.month, from: month))월").font(.title2.weight(.semibold))
                Text(String(cal.component(.year, from: month))).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let rate = monthRate {
                    Text("달성 \(rate)%").font(.footnote).foregroundStyle(.secondary).padding(.trailing, 8)
                }
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
            }
            .padding(.bottom, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(weekdays, id: \.self) {
                    Text($0).font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 4)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
        }
    }

    private var monthDays: [Date] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    /// 일요일 시작 기준으로 앞쪽 빈칸을 채운다
    private var cells: [Date?] {
        let days = monthDays
        guard let first = days.first else { return [] }
        let leading = cal.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: leading) + days.map { Optional($0) }
    }

    private var monthRate: Int? {
        let values = monthDays.compactMap { routines.completion(on: $0) }
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count) * 100).rounded())
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isFuture = day > cal.startOfDay(for: .now)
        return Button {
            selected = cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: day))")
                    .font(.callout)
                    .monospacedDigit()
                    .fontWeight(isToday ? .semibold : .regular)
                    .foregroundStyle(isToday ? Color(.systemBackground) : isFuture ? Color.secondary : Color.primary)
                    .frame(width: 32, height: 32)
                    .background {
                        if isToday {
                            Circle().fill(Color.primary)
                        } else if isSelected {
                            Circle().strokeBorder(Color.primary, lineWidth: 1)
                        }
                    }
                DayMarks(day: day, routines: routines)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shift(_ value: Int) {
        if let next = cal.date(byAdding: .month, value: value, to: month) { month = next }
    }
}

/// 날짜 아래 표시: 그날 달성도(잔디 점)와 약속이 있으면 작은 동그라미
struct DayMarks: View {
    let day: Date
    let routines: [Routine]

    var body: some View {
        HStack(spacing: 3) {
            completionDot(routines.completion(on: day))
            if routines.contains(where: { $0.kind == .once && Calendar.current.isDate($0.eventDate, inSameDayAs: day) }) {
                Circle().fill(Color.primary).frame(width: 5, height: 5)
            }
        }
    }

    /// 잔디처럼 4단계 진하기
    @ViewBuilder
    private func completionDot(_ ratio: Double?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 1.5)
        if let ratio {
            if ratio == 0 {
                shape.strokeBorder(Color.primary.opacity(0.25), lineWidth: 1).frame(width: 7, height: 7)
            } else {
                let level = ratio >= 1 ? 1 : ratio >= 0.67 ? 0.7 : ratio >= 0.34 ? 0.45 : 0.25
                shape.fill(Color.primary.opacity(level)).frame(width: 7, height: 7)
            }
        } else {
            Color.clear.frame(width: 7, height: 7)
        }
    }
}
