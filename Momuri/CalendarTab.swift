import SwiftUI
import SwiftData

/// 달력 탭: 평소엔 한 주만, 할 일은 "지금 / 오늘 / 완료(접힘) / 다가오는 것"으로 나눈다
struct CalendarTab: View {
    @Environment(\.modelContext) private var context
    let routines: [Routine]
    @AppStorage("calendarExpanded") private var expanded = false
    @State private var month = Date.now
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var showDone = false
    @State private var valueEntry: Routine?
    @State private var valueText = ""
    @State private var workoutLog: RoutineLog?
    @State private var studyRoutine: Routine?
    @State private var partRoutine: Routine?

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if expanded {
                    MonthCalendarView(month: $month, selected: $selected, routines: routines)
                } else {
                    WeekStrip(selected: $selected, routines: routines)
                }
                dayLists
                upcomingList
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .sheet(item: $workoutLog) { WorkoutLogView(log: $0) }
        .sheet(item: $studyRoutine) { StudyLogView(routine: $0, day: selected) }
        .sheet(item: $partRoutine) { routine in
            PartPickerSheet(routine: routine, day: selected) { log in
                partRoutine = nil
                // 시트가 닫힌 뒤 세트 입력 화면을 연다
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { workoutLog = log }
            }
            .presentationDetents([.height(220)])
        }
        .alert("거리 기록", isPresented: Binding(get: { valueEntry != nil }, set: { if !$0 { valueEntry = nil } })) {
            TextField("km", text: $valueText).keyboardType(.decimalPad)
            Button("기록") {
                if let routine = valueEntry, let value = Double(valueText.replacingOccurrences(of: ",", with: ".")), value > 0 {
                    RoutineActions.addValue(routine, value: value, on: selected, in: context)
                }
                valueText = ""
            }
            if let routine = valueEntry, routine.isDone(on: selected) {
                Button("이 날 기록 지우기", role: .destructive) {
                    RoutineActions.clear(routine, on: selected, in: context)
                }
            }
            Button("취소", role: .cancel) { valueText = "" }
        } message: {
            if let routine = valueEntry { Text(routine.displayName + " · " + String(localized: "이번 달 \(routine.statusLabel)")) }
        }
        .onChange(of: selected) { _, day in
            month = day
            showDone = false
        }
    }

    // MARK: - 머리

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(headerTitle).font(.title3.weight(.semibold))
            if !cal.isDateInToday(selected) {
                Button("오늘") { selected = cal.startOfDay(for: .now) }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(expanded ? "접기" : "한 달")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var headerTitle: String {
        let c = cal.dateComponents([.month, .day], from: selected)
        let weekday = selected.formatted(.dateTime.weekday(.abbreviated).locale(Locale.app))
        return String(localized: "\(c.month ?? 0)월 \(c.day ?? 0)일 \(weekday)")
    }

    // MARK: - 할 일 묶음

    private var isToday: Bool { cal.isDateInToday(selected) }
    private var isFuture: Bool { selected > cal.startOfDay(for: .now) }

    @ViewBuilder
    private var dayLists: some View {
        let items = routines.filter { $0.appears(on: selected) && $0.kind != .once }
        let appointments = routines.filter { $0.kind == .once && cal.isDate($0.eventDate, inSameDayAs: selected) }
        let done = items.filter { $0.isSettled(on: selected) && !isOpenEnded($0) }
        let pending = items.filter { !done.contains($0) }
        let urgent = isToday ? pending.filter { $0.urgency() != .none } : []
        let rest = pending.filter { !urgent.contains($0) }

        if items.isEmpty && appointments.isEmpty {
            Text(routines.isEmpty ? "오른쪽 위 + 로 첫 루틴을 만들어 보세요" : "할 일이 없어요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if !urgent.isEmpty {
            section("지금") { ForEach(urgent) { row($0) } }
        }
        if !appointments.isEmpty {
            section("약속") { ForEach(appointments) { row($0) } }
        }
        if !rest.isEmpty {
            section(isToday ? "오늘" : "할 일") {
                ForEach(rest) { row($0) }
            }
        }
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showDone.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("완료·쉼 \(done.count)개")
                        if !showDone {
                            Text("· " + done.map(\.displayName).joined(separator: ", "))
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: showDone ? "chevron.up" : "chevron.down").font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showDone {
                    ForEach(done) { row($0) }
                }
            }
        }
    }

    /// 주간·월간처럼 오늘 했어도 계속 쌓는 루틴은 완료로 접지 않는다
    private func isOpenEnded(_ routine: Routine) -> Bool {
        routine.kind == .weekly || routine.kind == .monthly
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary).padding(.bottom, 2)
            content()
        }
    }

    private func row(_ routine: Routine) -> some View {
        let done = routine.isDone(on: selected)
        // 경고색은 오늘을 볼 때만 의미가 있다
        let urgency = isToday ? routine.urgency() : .none
        let partial = routine.kind == .daily && !done && (routine.category == .study ? routine.dayTotal(on: selected) > 0 : routine.logCount(on: selected) > 0)
        let status = routine.kind == .once ? routine.eventTimeLabel + (routine.location.isEmpty ? "" : " · " + routine.location)
            : routine.listStatus(on: selected)
        return VStack(alignment: .leading, spacing: 8) {
            Button { tap(routine) } label: {
                HStack(spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : routine.isRestDay(selected) ? "moon.zzz" : partial ? "circle.lefthalf.filled" : "circle")
                        .font(.title3)
                        .foregroundStyle(urgency.color ?? .primary)
                    Text(routine.displayName)
                        .foregroundStyle(done && !isOpenEnded(routine) ? .secondary : .primary)
                        .lineLimit(1)
                    if routine.shareId != nil {
                        Image(systemName: "person.2").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(status)
                        .font(.subheadline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fontWeight(urgency != .none ? .semibold : .regular)
                        .foregroundStyle(urgency.color ?? .secondary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 폰 사용은 하루가 끝나면 자동으로 기록된다
            .disabled(isFuture || routine.category == .screen)
            .contextMenu {
                if routine.kind == .daily && routine.category != .screen && !done {
                    Button {
                        RoutineActions.toggleSkip(routine, on: selected, in: context)
                    } label: {
                        Label(routine.isSkipped(on: selected) ? "쉬기 취소" : "오늘은 쉬기", systemImage: "moon.zzz")
                    }
                }
            }
            if routine.category == .screen && isToday {
                ScreenTimeReportView().padding(.leading, 34).padding(.bottom, 8)
            }
        }
    }

    private func tap(_ routine: Routine) {
        if routine.kind == .monthly && routine.targetUnit == "km" {
            valueEntry = routine
        } else if routine.category == .study {
            studyRoutine = routine
        } else if routine.kind == .weekly {
            partRoutine = routine
        } else {
            RoutineActions.toggle(routine, on: selected, in: context)
        }
    }

    // MARK: - 다가오는 것

    /// 앞으로 2주 안의 약속
    @ViewBuilder
    private var upcomingList: some View {
        let limit = cal.date(byAdding: .day, value: 14, to: .now) ?? .now
        let items = routines
            .filter { $0.isUpcoming && $0.eventDate <= limit && !cal.isDate($0.eventDate, inSameDayAs: selected) }
            .sorted { $0.eventDate < $1.eventDate }
        if !items.isEmpty {
            section("다가오는 것") {
                ForEach(items.prefix(4)) { routine in
                    Button {
                        selected = cal.startOfDay(for: routine.eventDate)
                    } label: {
                        HStack {
                            Text(routine.displayName)
                            Spacer()
                            Text(routine.eventLabel(relative: false)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.subheadline)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 한 주 한 줄. 좌우로 밀면 지난주·다음 주.
struct WeekStrip: View {
    @Binding var selected: Date
    let routines: [Routine]

    private let cal = Calendar.current
    private let weekdays = [String(localized: "일"), String(localized: "월"), String(localized: "화"), String(localized: "수"),
                            String(localized: "목"), String(localized: "금"), String(localized: "토")]

    private var days: [Date] {
        guard let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                let isSelected = cal.isDate(day, inSameDayAs: selected)
                let isToday = cal.isDateInToday(day)
                Button { selected = cal.startOfDay(for: day) } label: {
                    VStack(spacing: 4) {
                        Text(weekdays[(cal.component(.weekday, from: day) - 1) % 7])
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(cal.component(.day, from: day))")
                            .font(.callout.monospacedDigit())
                            .fontWeight(isToday ? .semibold : .regular)
                            .foregroundStyle(isSelected ? Color(.systemBackground) : day > .now ? .secondary : .primary)
                            .frame(width: 34, height: 34)
                            .background {
                                if isSelected {
                                    Circle().fill(Color.primary)
                                } else if isToday {
                                    Circle().strokeBorder(Color.primary, lineWidth: 1)
                                }
                            }
                        DayMarks(day: day, routines: routines)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(i)
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            let step = value.translation.width < 0 ? 7 : -7
            if let next = cal.date(byAdding: .day, value: step, to: selected) {
                withAnimation(.snappy(duration: 0.2)) { selected = next }
            }
        })
    }
}

/// 헬스: 오늘 할 부위 고르기 → 세트 입력으로
struct PartPickerSheet: View {
    @Environment(\.modelContext) private var context
    let routine: Routine
    let day: Date
    let onPick: (RoutineLog) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(routine.displayName).font(.headline)
                Spacer()
                Text(routine.listStatus(on: day)).font(.subheadline).foregroundStyle(.secondary)
            }
            Text("오늘 한 부위를 고르면 세트를 적을 수 있어요").font(.caption).foregroundStyle(.secondary)
            PartChips(routine: routine, day: day) { part in
                let cal = Calendar.current
                if let log = routine.logs?.first(where: { $0.part == part && cal.isDate($0.date, inSameDayAs: day) }) {
                    onPick(log)
                } else {
                    onPick(RoutineActions.addPart(routine, part: part, on: day, in: context))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }
}
