import SwiftUI

/// 모무리쿤: 흰 둥근 네모 몸통, 굵은 검은 외곽선, 멀리 떨어진 점 눈, 길고 완만한 입, 아래 연회색 영역.
/// 몸 모양은 어느 상태에서도 같고, 눈·입·몸짓만 바뀐다. 외부 라이브러리 없이 SwiftUI만 쓴다.
///
/// - idle: 천천히 숨쉬기 + 가끔 눈 깜빡임
/// - happy: `completed`가 늘면 밝게 웃으며 살짝 점프
/// - celebrate: 오늘 할 일을 다 끝내면 크게 점프 + 반짝임 (그 뒤로도 웃는 얼굴과 반짝임 유지)
/// - sleepy: 쉬는 때 눈 감고 z, 숨을 더 느리게
/// - reminder: 약속·루틴 시간이 다가오면 몇 초마다 좌우로 살랑
///
/// 배터리: 끊임없이 도는 건 숨쉬기 하나뿐이고, 화면이 안 보이거나 앱이 백그라운드이거나
/// 저전력 모드·동작 줄이기에서는 멈춘다. 깜빡임·흔들기는 몇 초 간격의 Task로만 돈다.
struct MomuriKunView: View {
    /// 오늘 달성률 0...1
    var rate: Double
    /// 오늘 끝낸 개수. 늘어날 때마다 반응한다 (안 보일 때 늘었으면 다시 보일 때 반응)
    var completed: Int = 0
    var isResting = false
    var isReminding = false

    enum Mood: Equatable {
        case idle, happy, celebrate, sleepy, reminder
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var breath: CGFloat = 0
    @State private var blink = false
    @State private var flash: Mood?             // 완료 직후 잠깐 보이는 반응
    @State private var pending: Bool?           // 안 보일 때 생긴 반응 (true = 전부 완료)
    @State private var sparklePop = true
    @State private var motion: Motion = .hop
    @State private var trigger = 0
    @State private var width: CGFloat = 100

    var mood: Mood {
        if let flash { return flash }
        if isReminding { return .reminder }
        if isResting { return .sleepy }
        if rate >= 1 { return .celebrate }
        return .idle
    }

    private var face: MomuriKunFigure.Face {
        switch mood {
        case .idle, .reminder: .basic
        case .happy, .celebrate: .joy
        case .sleepy: .sleeping
        }
    }

    /// 계속 움직여도 되는 때
    private var lively: Bool { visible && scenePhase == .active && !reduceMotion && !lowPower }

    var body: some View {
        let unit = width / 120
        ZStack {
            MomuriKunFigure(face: face, blink: blink)
                .id(face)
                .transition(.opacity)
            decorations(unit: unit)
        }
        .aspectRatio(120 / 100, contentMode: .fit)
        .scaleEffect(x: 1 + 0.018 * breath, y: 1 - 0.022 * breath, anchor: .bottom)
        .keyframeAnimator(initialValue: Pose(), trigger: trigger) { content, pose in
            content
                .scaleEffect(x: pose.sx, y: pose.sy, anchor: .bottom)
                .rotationEffect(.degrees(pose.angle), anchor: .bottom)
                .offset(y: pose.y * unit)
        } keyframes: { _ in
            motion.keyframes
        }
        .animation(.easeInOut(duration: 0.35), value: face)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .onAppear {
            visible = true
            if let allDone = pending {
                pending = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    react(allDone: allDone)
                }
            }
        }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .task(id: lively) { breathe(lively) }
        .task(id: visible && scenePhase == .active && !lowPower) {
            guard visible && scenePhase == .active && !lowPower else { return }
            await blinkLoop()
        }
        .task(id: mood == .reminder && lively) {
            guard mood == .reminder && lively else { return }
            await reminderLoop()
        }
        .onChange(of: completed) { old, new in
            guard new > old else { return }
            if visible && scenePhase == .active {
                react(allDone: rate >= 1)
            } else {
                pending = (pending ?? false) || rate >= 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - 장식

    @ViewBuilder
    private func decorations(unit u: CGFloat) -> some View {
        if mood == .celebrate {
            Group {
                Sparkle().fill(.black).frame(width: 9 * u, height: 9 * u).position(x: 14 * u, y: 12 * u)
                Sparkle().fill(.black).frame(width: 7 * u, height: 7 * u).position(x: 106 * u, y: 8 * u)
                RoundedRectangle(cornerRadius: 1.6 * u).stroke(.black, lineWidth: 2 * u)
                    .frame(width: 7 * u, height: 7 * u).rotationEffect(.degrees(-12))
                    .position(x: 50 * u, y: 7 * u)
                RoundedRectangle(cornerRadius: 1.4 * u).stroke(.black, lineWidth: 2 * u)
                    .frame(width: 5.5 * u, height: 5.5 * u).rotationEffect(.degrees(14))
                    .position(x: 66 * u, y: 12 * u)
            }
            .scaleEffect(sparklePop || reduceMotion ? 1 : 0.2)
            .opacity(sparklePop || reduceMotion ? 1 : 0)
        }
        if mood == .sleepy {
            ForEach(0..<2, id: \.self) { i in
                Text("z")
                    .font(.system(size: (8 + CGFloat(i) * 3) * u, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .position(x: (100 + CGFloat(i) * 10) * u, y: (12 - CGFloat(i) * 9) * u)
            }
        }
        if mood == .reminder {
            AlertTicks().stroke(.black, style: StrokeStyle(lineWidth: 2.2 * u, lineCap: .round))
        }
    }

    // MARK: - 움직임

    private func breathe(_ on: Bool) {
        if on {
            withAnimation(.easeInOut(duration: isResting ? 3.6 : 2.6).repeatForever(autoreverses: true)) { breath = 1 }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { breath = 0 }
        }
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3...6)))
            guard !Task.isCancelled else { return }
            blink = true
            try? await Task.sleep(for: .milliseconds(120))
            blink = false
        }
    }

    private func reminderLoop() async {
        while !Task.isCancelled {
            motion = .shake
            trigger += 1
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func react(allDone: Bool) {
        if !reduceMotion {
            motion = allDone ? .celebrate : .hop
            trigger += 1
        }
        flash = allDone ? .celebrate : .happy
        if allDone {
            sparklePop = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.25)) { sparklePop = true }
        }
        Task {
            try? await Task.sleep(for: .seconds(allDone ? 1.8 : 1.1))
            flash = nil
        }
    }

    private var accessibilityText: String {
        let percent = Int((min(max(rate, 0), 1) * 100).rounded())
        let text: String = switch mood {
        case .idle: String(localized: "평온해요")
        case .happy: String(localized: "기뻐요")
        case .celebrate: String(localized: "오늘 할 일을 다 끝냈어요")
        case .sleepy: String(localized: "쉬는 중이에요")
        case .reminder: String(localized: "곧 할 일이 있어요")
        }
        return String(localized: "모무리쿤, \(text). 오늘 \(percent)% 달성")
    }
}

// MARK: - 키프레임

private struct Pose {
    var y: CGFloat = 0          // 위로 뜬 정도 (단위: 몸통 폭 120 기준)
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var angle: Double = 0
}

private enum Motion {
    case hop, celebrate, shake

    /// (값, 이 값에 도달하는 데 걸리는 초)
    typealias Track = [(CGFloat, Double)]

    var y: Track {
        switch self {
        case .hop: [(0, 0.1), (-16, 0.22), (0, 0.2), (-3, 0.12), (0, 0.14)]
        case .celebrate: [(0, 0.12), (-30, 0.28), (0, 0.24), (-22, 0.24), (0, 0.22), (-4, 0.12), (0, 0.14)]
        case .shake: [(0, 0.1)]
        }
    }

    var sx: Track {
        switch self {
        case .hop: [(1.12, 0.1), (0.92, 0.18), (1, 0.2), (1.12, 0.08), (0.97, 0.14), (1, 0.14)]
        case .celebrate: [(1.16, 0.12), (0.9, 0.2), (1, 0.24), (1.14, 0.08), (0.92, 0.2), (1, 0.18), (1.12, 0.08), (0.97, 0.14), (1, 0.16)]
        case .shake: [(1, 0.1)]
        }
    }

    var sy: Track {
        switch self {
        case .hop: [(0.86, 0.1), (1.1, 0.18), (1, 0.2), (0.88, 0.08), (1.04, 0.14), (1, 0.14)]
        case .celebrate: [(0.82, 0.12), (1.12, 0.2), (1, 0.24), (0.86, 0.08), (1.1, 0.2), (1, 0.18), (0.88, 0.08), (1.04, 0.14), (1, 0.16)]
        case .shake: [(1, 0.1)]
        }
    }

    var angle: Track {
        switch self {
        case .hop: [(0, 0.1)]
        case .celebrate: [(0, 0.4), (-5, 0.24), (5, 0.46), (0, 0.3)]
        case .shake: [(6, 0.12), (-6, 0.16), (5, 0.16), (-4, 0.15), (2, 0.14), (0, 0.14)]
        }
    }

    @KeyframesBuilder<Pose>
    var keyframes: some Keyframes<Pose> {
        KeyframeTrack(\.y) { for (v, d) in y { CubicKeyframe(v, duration: d) } }
        KeyframeTrack(\.sx) { for (v, d) in sx { CubicKeyframe(v, duration: d) } }
        KeyframeTrack(\.sy) { for (v, d) in sy { CubicKeyframe(v, duration: d) } }
        KeyframeTrack(\.angle) { for (v, d) in angle { CubicKeyframe(Double(v), duration: d) } }
    }
}

// MARK: - 그림

/// 120 x 100 좌표계: 몸통은 x 10~110, y 22~88. 위쪽 22는 장식 자리.
struct MomuriKunFigure: View {
    enum Face: Equatable { case basic, joy, sleeping }

    var face: Face
    var blink = false
    var shadow = true

    var body: some View {
        Canvas { ctx, size in
            let u = size.width / 120
            ctx.scaleBy(x: u, y: u)
            let body = Path(roundedRect: CGRect(x: 10, y: 22, width: 100, height: 66), cornerRadius: 25, style: .continuous)

            // 바닥 그림자
            if shadow { ctx.fill(Path(ellipseIn: CGRect(x: 6, y: 84, width: 108, height: 10)), with: .color(Color(white: 0.9))) }
            // 몸통, 아래 연회색 영역, 외곽선
            ctx.fill(body, with: .color(.white))
            var bottom = ctx
            bottom.clip(to: body)
            bottom.fill(Path(ellipseIn: CGRect(x: 18, y: 68, width: 84, height: 46)), with: .color(Color(white: 0.88)))
            ctx.stroke(body, with: .color(.black), style: StrokeStyle(lineWidth: 4.2, lineJoin: .round))

            drawFace(&ctx)
        }
    }

    private func drawFace(_ ctx: inout GraphicsContext) {
        let line = StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)
        let eyes = [CGPoint(x: 28, y: 54), CGPoint(x: 92, y: 54)]

        func mouth(from x0: CGFloat, to x1: CGFloat, y: CGFloat, sag: CGFloat) {
            var p = Path()
            p.move(to: CGPoint(x: x0, y: y))
            p.addQuadCurve(to: CGPoint(x: x1, y: y), control: CGPoint(x: (x0 + x1) / 2, y: y + sag * 2))
            ctx.stroke(p, with: .color(.black), style: line)
        }

        switch face {
        case .basic:
            for e in eyes {
                let h: CGFloat = blink ? 1.2 : 6.4
                ctx.fill(Path(ellipseIn: CGRect(x: e.x - 3.1, y: e.y - h / 2, width: 6.2, height: h)), with: .color(.black))
            }
            mouth(from: 42, to: 78, y: 61, sag: 2.6)
        case .joy:
            for e in eyes {
                var p = Path()
                p.move(to: CGPoint(x: e.x - 4.2, y: e.y + 2))
                p.addQuadCurve(to: CGPoint(x: e.x + 4.2, y: e.y + 2), control: CGPoint(x: e.x, y: e.y - 5))
                ctx.stroke(p, with: .color(.black), style: line)
            }
            var m = Path()
            m.move(to: CGPoint(x: 50, y: 59))
            m.addLine(to: CGPoint(x: 70, y: 59))
            m.addQuadCurve(to: CGPoint(x: 50, y: 59), control: CGPoint(x: 60, y: 78))
            m.closeSubpath()
            ctx.fill(m, with: .color(Color(white: 0.62)))
            ctx.stroke(m, with: .color(.black), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        case .sleeping:
            for e in eyes {
                var p = Path()
                p.move(to: CGPoint(x: e.x - 4.2, y: e.y))
                p.addQuadCurve(to: CGPoint(x: e.x + 4.2, y: e.y), control: CGPoint(x: e.x, y: e.y + 5))
                ctx.stroke(p, with: .color(.black), style: line)
            }
            mouth(from: 46, to: 74, y: 62, sag: 2)
        }
    }
}

/// 네 갈래 반짝임
private struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let k: CGFloat = 0.18
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: c.y), control: CGPoint(x: c.x + r.width * k, y: c.y - r.height * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.maxY), control: CGPoint(x: c.x + r.width * k, y: c.y + r.height * k))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: c.y), control: CGPoint(x: c.x - r.width * k, y: c.y + r.height * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.minY), control: CGPoint(x: c.x - r.width * k, y: c.y - r.height * k))
        return p
    }
}

/// 약속 알림 때 양옆 위에 그리는 짧은 선 두 쌍
private struct AlertTicks: Shape {
    func path(in r: CGRect) -> Path {
        let u = r.width / 120
        var p = Path()
        for (a, b) in [((6.0, 18.0), (1.0, 13.0)), ((3.0, 27.0), (-3.0, 25.0)),
                       ((114.0, 18.0), (119.0, 13.0)), ((117.0, 27.0), (123.0, 25.0))] {
            p.move(to: CGPoint(x: a.0 * u, y: a.1 * u))
            p.addLine(to: CGPoint(x: b.0 * u, y: b.1 * u))
        }
        return p
    }
}

#Preview {
    VStack(spacing: 28) {
        HStack(spacing: 24) {
            MomuriKunView(rate: 0.2).frame(width: 110)
            MomuriKunView(rate: 1).frame(width: 110)
        }
        HStack(spacing: 24) {
            MomuriKunView(rate: 0, isResting: true).frame(width: 110)
            MomuriKunView(rate: 0.4, isReminding: true).frame(width: 110)
        }
    }
    .padding()
}
