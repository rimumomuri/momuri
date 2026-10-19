import FamilyControls
import SwiftUI
import SwiftData

/// 분류에 따라 필요한 설정만 보여주는 루틴 생성·수정 화면
struct RoutineFormView: View {
    @Environment(\.modelContext) private var context
    let routine: Routine?
    let category: RoutineCategory
    let onFinish: () -> Void

    @State private var name = ""
    @State private var kind = RoutineKind.daily
    @State private var intervalValue = 1
    @State private var unit = IntervalUnit.month
    @State private var customInterval = false
    @State private var reminder = RoutineFormView.time(9, 0)
    @State private var doseTimes = [RoutineFormView.time(9, 0)]
    @State private var remindDaysBefore = 3
    @State private var showInWidget = true
    @State private var hasLastDone = false
    @State private var lastDone = Date.now
    @State private var parts: [String] = []
    @State private var customPart = ""
    @State private var isCritical = false
    @State private var useAlarm = false
    @State private var restWeekdays: Set<Int> = []
    @State private var weekendOnly = false
    @State private var targetValue: Double = 30
    @State private var targetUnit = "km"
    @State private var windowStart = RoutineFormView.time(12, 0)
    @State private var windowEnd = RoutineFormView.time(20, 0)
    @State private var showLive = true
    @State private var autoHealth = false
    @State private var goalMinutes = 120
    @State private var screenSelection = FamilyActivitySelection()
    @State private var showingAppPicker = false
    @State private var eventDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    @State private var allDay = false
    @State private var location = ""
    @State private var remindOffsets: Set<Int> = [60, 1440]
    @State private var hasExam = true
    @State private var examDate = Calendar.current.date(byAdding: .month, value: 2, to: .now) ?? .now
    @State private var studyGoal: Double = 30
    @State private var studyUnit = "문제"
    @State private var studyTogether = false
    @State private var studyStart = RoutineFormView.time(21, 0)
    @State private var studyEnd = RoutineFormView.time(22, 0)
    @State private var confirmingDelete = false
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    init(routine: Routine?, category: RoutineCategory? = nil, onFinish: @escaping () -> Void) {
        self.routine = routine
        self.category = routine?.category ?? category ?? .other
        self.onFinish = onFinish
    }

    private static let presets: [(value: Int, unit: IntervalUnit)] = [
        (1, .week), (2, .week), (1, .month), (2, .month), (3, .month),
    ]
    private static let reminderChoices: [(minutes: Int, label: String)] = [
        (0, String(localized: "정각")), (10, String(localized: "10분 전")), (60, String(localized: "1시간 전")), (1440, String(localized: "하루 전")),
    ]

    /// 이름은 저장 값(한국어). 칩과 이름 칸에는 localizedValue 로 보여 준다.
    private static let petPresets: [(name: String, value: Int, unit: IntervalUnit)] = [
        ("샴푸", 2, .week), ("발톱 깎기", 2, .week), ("귀 청소", 1, .week),
        ("심장사상충 약", 1, .month), ("구충제", 3, .month), ("미용", 2, .month), ("종합 백신", 12, .month),
    ]

    /// 저장 값(한국어). 화면에는 localizedValue 로 보여 준다.
    private static let presetParts = StoredValue.parts

    private var effectiveKind: RoutineKind { category.fixedKind ?? kind }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (effectiveKind != .weekly || !parts.isEmpty)
            && (category != .diet || Self.minutes(windowEnd) > Self.minutes(windowStart))
    }

    private var namePlaceholder: String {
        switch category {
        case .medicine: String(localized: "약 이름")
        case .care: String(localized: "제모, 미용실, 피부과…")
        case .gym: String(localized: "헬스")
        case .cardio: String(localized: "러닝")
        case .diet: String(localized: "식단")
        case .screen: String(localized: "폰 사용")
        case .appointment: String(localized: "누구와 무엇을")
        case .study: String(localized: "정보처리기사, 토익…")
        case .pet: String(localized: "샴푸, 심장사상충…")
        default: String(localized: "무엇을 할까요?")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(category.title, systemImage: category.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(namePlaceholder, text: $name)
                        .font(.title2.weight(.semibold))
                        .focused($nameFocused)
                        .submitLabel(.done)
                }

                if category == .other {
                    section("반복") {
                        HStack(spacing: 8) {
                            kindCard(.daily, title: "매일", detail: "매일 체크")
                            kindCard(.interval, title: "주기", detail: "몇 주·달에 한 번")
                            kindCard(.weekly, title: "주간", detail: "한 주에 채우기")
                        }
                    }
                }

                switch effectiveKind {
                case .daily:
                    if category == .medicine {
                        doseTimesSection
                    } else if category == .diet {
                        dietSection
                    } else if category == .screen {
                        screenSection
                    } else if category == .study {
                        studySection
                    } else {
                        reminderSection
                    }
                case .interval:
                    if category == .pet { petPresetSection }
                    intervalSections
                    reminderSection
                case .weekly:
                    partsSection
                    reminderSection
                case .monthly:
                    targetSection
                case .once:
                    appointmentSection
                }

                if effectiveKind == .daily && category != .screen && category != .diet {
                    section("쉬는 요일") {
                        HStack(spacing: 6) {
                            ForEach(Array([String(localized: "일"), String(localized: "월"), String(localized: "화"), String(localized: "수"), String(localized: "목"), String(localized: "금"), String(localized: "토")].enumerated()), id: \.offset) { i, label in
                                chip(label, selected: restWeekdays.contains(i + 1)) {
                                    if restWeekdays.contains(i + 1) { restWeekdays.remove(i + 1) } else { restWeekdays.insert(i + 1) }
                                }
                            }
                        }
                        Text("쉬는 날은 해야 할 날에서 빠져서 잔디가 끊기지 않아요. 그날그날은 목록에서 길게 눌러 '오늘은 쉬기'도 돼요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if effectiveKind != .monthly && effectiveKind != .once && category != .diet && category != .screen {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("꼭 해야 하는 루틴", isOn: $isCritical)
                        Text("기한이 다가오면 주황, 놓치면 빨강으로 표시해요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isCritical && effectiveKind != .weekly {
                            Toggle("알람으로 울리기", isOn: $useAlarm)
                                .padding(.top, 8)
                                .onChange(of: useAlarm) { _, on in
                                    if on { Task { if !(await AlarmScheduler.requestAuthorization()) { useAlarm = false } } }
                                }
                            Text("무음 모드여도 알람처럼 울려요. 알람의 '완료'를 누르면 바로 기록돼요.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Toggle("홈 위젯에 표시", isOn: $showInWidget)

                if routine != nil {
                    Button("루틴 삭제", role: .destructive) { confirmingDelete = true }
                        .font(.subheadline)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text(routine == nil ? "만들기" : "저장")
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.primary.opacity(canSave ? 1 : 0.2)))
            }
            .disabled(!canSave)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .background(.background)
        }
        .navigationTitle(category == .appointment ? (routine == nil ? "새 약속" : "약속 수정") : (routine == nil ? "새 루틴" : "루틴 수정"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("이 루틴과 기록을 모두 삭제할까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive, action: delete)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if routine == nil { applyDefaults(); nameFocused = name.isEmpty } else { load() }
        }
    }

    // MARK: - 분류별 섹션

    private var doseTimesSection: some View {
        section("복용 시간") {
            ForEach(Array(doseTimes.indices), id: \.self) { i in
                HStack {
                    Text("\(i + 1)회").foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("\(i + 1)회", selection: Binding(
                        get: { i < doseTimes.count ? doseTimes[i] : .now },
                        set: { if i < doseTimes.count { doseTimes[i] = $0 } }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    if doseTimes.count > 1 {
                        Button { doseTimes.remove(at: i) } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("\(i + 1)회 삭제")
                    }
                }
            }
            Button {
                doseTimes.append(Self.time(21, 0))
            } label: {
                Label("복용 시간 추가", systemImage: "plus").font(.subheadline)
            }
            .padding(.top, 2)
        }
    }

    private var reminderSection: some View {
        section("알림 시간") {
            DatePicker("알림 시간", selection: $reminder, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var intervalSections: some View {
        section("주기") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Self.presets.indices, id: \.self) { i in
                    let p = Self.presets[i]
                    chip("\(p.value)\(p.unit.label)",
                         selected: !customInterval && intervalValue == p.value && unit == p.unit) {
                        customInterval = false
                        intervalValue = p.value
                        unit = p.unit
                    }
                }
                chip(String(localized: "직접"), selected: customInterval) { customInterval = true }
            }
            if customInterval {
                HStack {
                    Stepper("\(intervalValue)", value: $intervalValue, in: 1...365).fixedSize()
                    Picker("단위", selection: $unit) {
                        ForEach(IntervalUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("주말에 맞추기", isOn: $weekendOnly)
                Text("예정일이 평일이면 그 주 토·일 중에 하면 돼요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }

        if routine == nil {
            section("마지막으로 한 날") {
                HStack(spacing: 8) {
                    chip(String(localized: "아직 안 함"), selected: !hasLastDone) { hasLastDone = false }
                    chip(String(localized: "날짜 선택"), selected: hasLastDone) { hasLastDone = true }
                }
                if hasLastDone {
                    DatePicker("날짜", selection: $lastDone, in: ...Date.now, displayedComponents: .date)
                        .padding(.top, 4)
                }
            }
        }

        section("미리 알림") {
            Stepper(remindDaysBefore == 0 ? "당일에만" : "\(remindDaysBefore)일 전부터",
                    value: $remindDaysBefore, in: 0...30)
        }
    }

    private var partsSection: some View {
        section("이번 주에 채울 항목") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Self.presetParts + parts.filter { !Self.presetParts.contains($0) }, id: \.self) { part in
                    chip(part.localizedValue, selected: parts.contains(part)) { togglePart(part) }
                }
            }
            HStack {
                TextField("직접 추가", text: $customPart).onSubmit(addCustomPart)
                Button("추가", action: addCustomPart)
                    .disabled(customPart.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.subheadline)
            .padding(.top, 4)
            if !parts.isEmpty {
                Text("순서: \(parts.map(\.localizedValue).joined(separator: " → "))")
                    .font(.footnote)
                    .padding(.top, 4)
                Text("고른 순서대로 다음 항목을 알려줘요. 이번 주 안에 끝내기 빠듯할 때만 알림이 와요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dietSection: some View {
        let start = Self.minutes(windowStart)
        let end = Self.minutes(windowEnd)
        return section("식사 시간대") {
            HStack(spacing: 8) {
                chip("16:8", selected: start == 720 && end == 1200) { setWindow(12, 20) }
                chip("18:6", selected: start == 720 && end == 1080) { setWindow(12, 18) }
                chip("14:10", selected: start == 600 && end == 1200) { setWindow(10, 20) }
            }
            HStack {
                DatePicker("시작", selection: $windowStart, displayedComponents: .hourAndMinute)
                Text("–").foregroundStyle(.secondary).padding(.horizontal, 8)
                DatePicker("끝", selection: $windowEnd, displayedComponents: .hourAndMinute)
            }
            .labelsHidden()
            .padding(.top, 4)
            Text(end > start
                 ? "식사 \((end - start) / 60)시간 · 금식 \((1440 - (end - start)) / 60)시간. 시작·종료 30분 전·금식 시작에 알려요."
                 : "끝나는 시간이 시작보다 늦어야 해요")
                .font(.caption)
                .foregroundStyle(end > start ? Color.secondary : Color.red)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Dynamic Island에 표시", isOn: $showLive)
                Text("금식·식사 남은 시간을 잠금화면과 Dynamic Island에 띄워요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private var studySection: some View {
        VStack(alignment: .leading, spacing: 32) {
            section("시험일") {
                Toggle("시험일 정하기", isOn: $hasExam)
                if hasExam {
                    DatePicker("시험일", selection: $examDate, in: Date.now..., displayedComponents: .date)
                }
            }
            section("하루 목표") {
                HStack(spacing: 8) {
                    ForEach(["문제", "분", "페이지"], id: \.self) { unit in
                        chip(unit.localizedValue, selected: studyUnit == unit) {
                            studyUnit = unit
                            studyGoal = unit == "분" ? 60 : unit == "페이지" ? 20 : 30
                        }
                    }
                }
                Stepper("하루 \(Routine.format(studyGoal))\(studyUnit.localizedValue)", value: $studyGoal,
                        in: 1...600, step: studyUnit == "분" ? 10 : 5)
                    .padding(.top, 4)
            }
            section("알림") {
                DatePicker("목표를 못 채웠으면 알림", selection: $reminder, displayedComponents: .hourAndMinute)
            }
            section("같이 공부") {
                Toggle("같이 공부할 시간 정하기", isOn: $studyTogether)
                if studyTogether {
                    HStack {
                        DatePicker("시작", selection: $studyStart, displayedComponents: .hourAndMinute)
                        Text("–").foregroundStyle(.secondary).padding(.horizontal, 8)
                        DatePicker("끝", selection: $studyEnd, displayedComponents: .hourAndMinute)
                    }
                    .labelsHidden()
                }
                Text("루틴을 공유하면 서로의 오늘 진행량과 '공부 중' 상태를 볼 수 있어요. 정한 시간이 되면 같이 알림이 와요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appointmentSection: some View {
        VStack(alignment: .leading, spacing: 32) {
            section("언제") {
                DatePicker("날짜", selection: $eventDate, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                Toggle("하루 종일", isOn: $allDay)
            }
            section("어디서") {
                TextField("장소 (선택)", text: $location)
            }
            if !allDay {
                section("미리 알림") {
                    HStack(spacing: 8) {
                        ForEach(Self.reminderChoices, id: \.minutes) { choice in
                            chip(choice.label, selected: remindOffsets.contains(choice.minutes)) {
                                if remindOffsets.contains(choice.minutes) {
                                    remindOffsets.remove(choice.minutes)
                                } else {
                                    remindOffsets.insert(choice.minutes)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var petPresetSection: some View {
        section("자주 하는 것") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Self.petPresets, id: \.name) { preset in
                    chip(preset.name.localizedValue, selected: name == preset.name.localizedValue) {
                        name = preset.name.localizedValue
                        intervalValue = preset.value
                        unit = preset.unit
                        customInterval = !Self.presets.contains { $0.value == preset.value && $0.unit == preset.unit }
                    }
                }
            }
            Text("고르면 이름과 주기가 채워져요. 병원 진료처럼 날짜가 정해진 건 약속으로 만들어요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var screenSection: some View {
        let apps = screenSelection.applicationTokens.count
        let categories = screenSelection.categoryTokens.count
        return section("하루 목표") {
            Stepper("하루 \(ScreenTimeShared.label(minutes: goalMinutes))", value: $goalMinutes, in: 30...600, step: 30)
            Button {
                Task {
                    if await ScreenTimeManager.requestAuthorization() { showingAppPicker = true }
                }
            } label: {
                HStack {
                    Text("세는 앱·카테고리")
                    Spacer()
                    Text(apps + categories == 0 ? "고르기" : "앱 \(apps) · 카테고리 \(categories)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .familyActivityPicker(isPresented: $showingAppPicker, selection: $screenSelection)
            Text(apps + categories == 0
                 ? "전체를 세려면 카테고리를 모두 골라요. Screen Time 권한이 필요해요."
                 : "목표의 80%와 100%에 알리고, 목표 안에서 끝난 날이 자동으로 채워져요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func setWindow(_ startHour: Int, _ endHour: Int) {
        windowStart = Self.time(startHour, 0)
        windowEnd = Self.time(endHour, 0)
    }

    private var targetSection: some View {
        section("이번 달 목표") {
            HStack(spacing: 8) {
                chip(String(localized: "거리 (km)"), selected: targetUnit == "km") {
                    targetUnit = "km"
                    targetValue = 30
                }
                chip(String(localized: "횟수"), selected: targetUnit == "회") {
                    targetUnit = "회"
                    targetValue = 8
                }
            }
            Stepper("한 달 \(Routine.format(targetValue))\(targetUnit.localizedValue)",
                    value: $targetValue,
                    in: targetUnit == "km" ? 5...500 : 1...60,
                    step: targetUnit == "km" ? 5 : 1)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("건강 앱에서 자동 기록", isOn: $autoHealth)
                    .onChange(of: autoHealth) { _, on in
                        if on { Task { await HealthSync.requestAuthorization() } }
                    }
                Text(autoHealth
                     ? "건강 앱(애플워치·러닝 앱)의 러닝 운동이 앱을 열 때 자동으로 들어와요. 직접 적은 기록도 함께 쌓여요."
                     : targetUnit == "km" ? "달린 날 오늘 목록에서 눌러 거리를 적어요." : "한 날 오늘 목록에서 체크해요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - 공통 조각

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func kindCard(_ value: RoutineKind, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        let selected = kind == value
        return Button {
            withAnimation(.snappy(duration: 0.2)) { kind = value }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(selected ? 0.05 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(selected ? 1 : 0.15), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.primary.opacity(selected ? 1 : 0)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.15)))
        }
        .buttonStyle(.plain)
    }

    private static func time(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    private static func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func togglePart(_ part: String) {
        if let i = parts.firstIndex(of: part) { parts.remove(at: i) } else { parts.append(part) }
    }

    private func addCustomPart() {
        let part = customPart.trimmingCharacters(in: .whitespaces)
        guard !part.isEmpty else { return }
        if !parts.contains(part) { parts.append(part) }
        customPart = ""
    }

    // MARK: - 불러오기·저장

    /// 분류에 맞는 기본값
    private func applyDefaults() {
        switch category {
        case .medicine:
            isCritical = true
            doseTimes = [Self.time(8, 0)]
        case .gym:
            name = "헬스".localizedValue
            parts = StoredValue.defaultParts
            reminder = Self.time(19, 0)
        case .cardio:
            name = "러닝".localizedValue
            autoHealth = HealthSync.isAvailable
        case .care:
            weekendOnly = true
        case .diet:
            name = "식단".localizedValue
        case .appointment:
            showInWidget = false
        case .study:
            reminder = Self.time(22, 0)
        case .screen:
            name = "폰 사용".localizedValue
            screenSelection = ScreenTimeManager.selection
        default:
            break
        }
    }

    private func load() {
        guard let routine else { return }
        name = routine.displayName
        kind = routine.kind
        intervalValue = routine.intervalValue
        unit = routine.intervalUnit
        customInterval = !Self.presets.contains { $0.value == intervalValue && $0.unit == unit }
        reminder = Self.time(routine.reminderHour, routine.reminderMinute)
        doseTimes = routine.times.map { Self.time($0 / 60, $0 % 60) }
        remindDaysBefore = routine.remindDaysBefore
        showInWidget = routine.showInWidget
        parts = routine.parts
        isCritical = routine.isCritical
        useAlarm = routine.useAlarm
        restWeekdays = Set(routine.restWeekdays)
        weekendOnly = routine.weekendOnly
        targetValue = routine.targetValue
        targetUnit = routine.targetUnit
        windowStart = Self.time(routine.windowStart / 60, routine.windowStart % 60)
        windowEnd = Self.time(routine.windowEnd / 60, routine.windowEnd % 60)
        showLive = routine.showLive
        autoHealth = routine.autoHealth
        goalMinutes = routine.goalMinutes
        eventDate = routine.eventDate
        allDay = routine.allDay
        location = routine.location
        remindOffsets = Set(routine.remindOffsets)
        hasExam = routine.examDate != nil
        examDate = routine.examDate ?? examDate
        studyGoal = routine.studyGoal
        studyUnit = routine.studyUnit
        studyTogether = routine.studyTogether
        studyStart = Self.time(routine.studyStart / 60, routine.studyStart % 60)
        studyEnd = Self.time(routine.studyEnd / 60, routine.studyEnd % 60)
        if routine.category == .screen { screenSelection = ScreenTimeManager.selection }
    }

    private func save() {
        let kind = effectiveKind
        let target: Routine
        if let routine {
            target = routine
        } else {
            let count = (try? context.fetchCount(FetchDescriptor<Routine>())) ?? 0
            target = Routine(name: name, kind: kind, sortOrder: count)
            target.category = category
            context.insert(target)
            if kind == .interval && hasLastDone {
                let log = RoutineLog(date: Calendar.current.startOfDay(for: lastDone))
                context.insert(log)
                target.logs?.append(log)
            }
        }
        // 이름 칸에는 번역된 이름을 보여 주므로, 추천·기본 이름이면 한국어로 되돌려 저장한다
        target.name = StoredValue.key(forDisplayed: name.trimmingCharacters(in: .whitespaces))
        target.kind = kind
        target.intervalValue = intervalValue
        target.intervalUnit = unit
        let first = category == .medicine ? Self.minutes(doseTimes.min() ?? reminder)
            : category == .diet ? Self.minutes(windowEnd)
            : Self.minutes(reminder)
        target.reminderHour = first / 60
        target.reminderMinute = first % 60
        target.reminderTimes = category == .medicine && doseTimes.count > 1 ? doseTimes.map(Self.minutes).sorted() : []
        target.remindDaysBefore = remindDaysBefore
        target.showInWidget = showInWidget
        target.parts = kind == .weekly ? parts : []
        target.isCritical = kind != .monthly && isCritical
        target.useAlarm = target.isCritical && useAlarm
        target.restWeekdays = kind == .daily ? restWeekdays.sorted() : []
        target.weekendOnly = kind == .interval && weekendOnly
        target.targetValue = kind == .monthly ? targetValue : 0
        target.targetUnit = targetUnit
        target.windowStart = Self.minutes(windowStart)
        target.windowEnd = Self.minutes(windowEnd)
        target.showLive = showLive
        target.autoHealth = kind == .monthly && autoHealth
        target.goalMinutes = goalMinutes
        target.eventDate = allDay ? Calendar.current.startOfDay(for: eventDate) : eventDate
        target.allDay = allDay
        target.location = location.trimmingCharacters(in: .whitespaces)
        target.remindOffsets = remindOffsets.sorted()
        target.examDate = category == .study && hasExam ? Calendar.current.startOfDay(for: examDate) : nil
        target.studyGoal = studyGoal
        target.studyUnit = studyUnit
        target.studyTogether = studyTogether
        target.studyStart = Self.minutes(studyStart)
        target.studyEnd = Self.minutes(studyEnd)
        RoutineActions.commit(context)
        if category == .screen {
            ScreenTimeManager.selection = screenSelection
            ScreenTimeManager.startMonitoring(goalMinutes: goalMinutes)
        }
        if target.autoHealth { Task { await HealthSync.sync(context: context) } }
        DietLiveActivity.sync(context: context)
        onFinish()
    }

    private func delete() {
        guard let routine else { return }
        if routine.category == .screen { ScreenTimeManager.stopMonitoring() }
        // 지운 모델을 화면이 읽으면 멈출 수 있어서, 화면을 먼저 닫고 지운다
        onFinish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            context.delete(routine)
            RoutineActions.commit(context)
            DietLiveActivity.sync(context: context)
        }
    }
}

/// 최근 기록 목록 (주간형 외)
struct RecentLogsView: View {
    let routine: Routine

    private var recent: [RoutineLog] {
        routine.activeLogs.sorted { $0.date > $1.date }.prefix(8).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 기록").font(.caption).foregroundStyle(.secondary)
            if recent.isEmpty {
                Text("아직 기록이 없어요").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(recent) { log in
                HStack {
                    Text(log.date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale.app)))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if log.externalID != nil {
                        Image(systemName: "heart").font(.caption).foregroundStyle(.secondary)
                    }
                    if let value = log.value {
                        Text(Routine.format(value) + (routine.category == .study ? routine.studyUnit : routine.targetUnit).localizedValue)
                    } else if routine.kind == .daily && routine.times.count > 1 {
                        Text(log.date.formatted(.dateTime.hour().minute()))
                    } else {
                        Text("완료")
                    }
                }
                .font(.subheadline)
            }
        }
    }
}

/// 주간형 루틴의 최근 4주 달성률과 항목 기록
struct WeeklyHistoryView: View {
    let routine: Routine
    @State private var openedLog: RoutineLog?

    private var weeks: [Date] {
        (0..<4).reversed().compactMap { Routine.weekCalendar.date(byAdding: .weekOfYear, value: -$0, to: .now) }
    }

    private var recentLogs: [RoutineLog] {
        (routine.logs ?? []).filter { $0.part != nil }.sorted { $0.date > $1.date }.prefix(10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("최근 4주 달성").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(weeks, id: \.self) { week in
                        let rate = routine.weekRate(of: week) ?? 0
                        VStack(spacing: 6) {
                            Text("\(Int((rate * 100).rounded()))%").font(.caption2).monospacedDigit()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 48)
                                .overlay(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.primary).frame(height: 48 * rate)
                                }
                            Text(label(for: week)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("최근 기록").font(.caption).foregroundStyle(.secondary)
                if recentLogs.isEmpty {
                    Text("아직 기록이 없어요").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(recentLogs) { log in
                    Button { openedLog = log } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(log.date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale.app)))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text((log.part ?? "").localizedValue)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .font(.subheadline)
                            if !log.exercises.isEmpty {
                                Text(log.exercises.map(\.localizedValue).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !bestRecords.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("종목별 최고 기록").font(.caption).foregroundStyle(.secondary)
                    ForEach(bestRecords, id: \.exercise) { record in
                        HStack {
                            Text(record.exercise.localizedValue)
                            Spacer()
                            Text(record.summary).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .sheet(item: $openedLog) { WorkoutLogView(log: $0) }
    }

    private var bestRecords: [WorkoutSet] {
        routine.usedExercises(for: nil).prefix(8).compactMap { routine.bestSet(of: $0) }.filter { $0.weight > 0 }
    }

    private func label(for week: Date) -> String {
        if Routine.weekCalendar.isDate(week, equalTo: .now, toGranularity: .weekOfYear) { return String(localized: "이번 주") }
        guard let start = Routine.weekCalendar.dateInterval(of: .weekOfYear, for: week)?.start else { return "" }
        let c = Calendar.current.dateComponents([.month, .day], from: start)
        return "\(c.month ?? 0)/\(c.day ?? 0)~"
    }
}
