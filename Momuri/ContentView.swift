import SwiftUI
import SwiftData

enum HomeMode: String, CaseIterable {
    case home = "홈"
    case calendar = "달력"
    case routines = "루틴"

    /// rawValue 는 @AppStorage 에 저장되는 값이라 그대로 두고, 화면에는 이 이름을 보여 준다
    var title: String {
        switch self {
        case .home: String(localized: "홈")
        case .calendar: String(localized: "달력")
        case .routines: String(localized: "루틴")
        }
    }
}

enum RoutineRoute: Hashable {
    case new
    case create(RoutineCategory)
    case edit(Routine)
    case detail(Routine)
}

struct ContentView: View {
    @Query(sort: \Routine.sortOrder) private var routines: [Routine]
    @AppStorage("homeMode") private var mode: HomeMode = .home
    @State private var path: [RoutineRoute] = []
    @State private var showingChat = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                HStack {
                    ModeSwitch(mode: $mode)
                    Spacer()
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").font(.body).frame(width: 36, height: 40)
                    }
                    .accessibilityLabel("설정")
                    Button { path.append(.new) } label: {
                        Image(systemName: "plus").font(.title3).frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("새 루틴")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)

                switch mode {
                case .home:
                    ScrollView { HomeBlobView(routines: routines) { path.append(.detail($0)) } }
                case .calendar:
                    CalendarTab(routines: routines)
                case .routines:
                    RoutineListView(routines: routines,
                                    onCreate: { path.append(.new) },
                                    onOpen: { path.append(.detail($0)) })
                }
            }
            .overlay(alignment: .bottomTrailing) { chatButton }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RoutineRoute.self) { route in
                switch route {
                case .new:
                    CategoryPickerView(onPick: { path.append(.create($0)) }, onJoined: { path.removeAll() })
                case .create(let category):
                    RoutineFormView(routine: nil, category: category) { path.removeAll() }
                case .edit(let routine):
                    RoutineFormView(routine: routine) { path.removeAll() }
                case .detail(let routine):
                    RoutineDetailView(routine: routine) { path.append(.edit(routine)) }
                }
            }
        }
        .tint(.primary)
        .sheet(isPresented: $showingChat) { ChatView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .task { NotificationScheduler.requestAuthorization() }
    }

    private var chatButton: some View {
        Button { showingChat = true } label: {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Color(.systemBackground))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.primary))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
        .accessibilityLabel("AI 채팅")
        .padding(20)
    }
}

struct ModeSwitch: View {
    @Binding var mode: HomeMode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { mode = m }
                } label: {
                    Text(m.title)
                        .font(.subheadline.weight(.medium))
                        // 일본어(カレンダー 등)는 글자가 길어서 줄바꿈되지 않게 조금 줄인다
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(mode == m ? Color(.systemBackground) : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            if mode == m {
                                Capsule().fill(Color.primary).matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}
