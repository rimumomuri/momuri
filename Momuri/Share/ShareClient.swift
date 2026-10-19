import Foundation

/// momuri 공유 서버 API. 계정 없이 이름과 기기에 저장한 토큰만 쓴다.
enum ShareClient {
    struct Member: Codable {
        let id: String
        let token: String
        let name: String
    }

    struct ServerError: LocalizedError {
        let message: String
        var status = 0
        /// 서버가 보내는 한국어 오류 문장도 화면 언어로 바꿔 보여 준다
        var errorDescription: String? { message.localizedValue }
    }

    static var baseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "MomuriServerURL") as? String ?? "http://localhost:8787"
        return URL(string: raw)!
    }

    // 개인용 앱이라 토큰은 UserDefaults에 둔다
    static var me: Member? {
        get { UserDefaults.standard.data(forKey: "shareMember").flatMap { try? JSONDecoder().decode(Member.self, from: $0) } }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "shareMember") }
    }

    static func register(name: String) async throws -> Member {
        let member: Member = try await request("POST", "/members", body: ["name": name], auth: false)
        me = member
        return member
    }

    static func createShare(_ routine: RoutineDefinition) async throws -> ShareView {
        try await request("POST", "/shares", body: ["routine": routine])
    }

    static func join(code: String) async throws -> ShareView {
        try await request("POST", "/shares/join", body: ["code": code])
    }

    static func fetch(_ id: String) async throws -> ShareView {
        try await request("GET", "/shares/\(id)", body: Optional<[String: String]>.none)
    }

    private struct DaysBody: Encodable {
        let days: [String]
        let progress: [String: Double]
    }

    private struct StatusBody: Encodable {
        let studyingSince: Date?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(studyingSince, forKey: .studyingSince)  // null도 보낸다
        }
        enum CodingKeys: String, CodingKey { case studyingSince }
    }

    static func pushDays(_ id: String, days: [String], progress: [String: Double]) async throws -> ShareView {
        try await request("PUT", "/shares/\(id)/days", body: DaysBody(days: days, progress: progress))
    }

    static func cheer(_ id: String, to memberID: String) async throws -> ShareView {
        try await request("POST", "/shares/\(id)/cheers", body: ["to": memberID])
    }

    static func setStudying(_ id: String, since: Date?) async throws -> ShareView {
        try await request("PUT", "/shares/\(id)/status", body: StatusBody(studyingSince: since))
    }

    static func updateRoutine(_ id: String, _ routine: RoutineDefinition) async throws -> ShareView {
        try await request("PUT", "/shares/\(id)/routine", body: ["routine": routine])
    }

    static func leave(_ id: String) async throws {
        let _: Empty? = try await request("DELETE", "/shares/\(id)/members/me", body: Optional<[String: String]>.none)
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private struct Empty: Decodable {}
    private struct ErrorBody: Decodable { let error: String }

    private static func request<Body: Encodable, T: Decodable>(_ method: String, _ path: String, body: Body?, auth: Bool = true, retried: Bool = false) async throws -> T {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if auth {
            guard let token = me?.token else { throw ServerError(message: String(localized: "먼저 이름을 정해 주세요")) }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        if let body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            req.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 서버를 옮기거나 초기화해서 토큰이 무효면 같은 이름으로 다시 등록하고 한 번 더 시도
        if status == 401, auth, !retried, let name = me?.name {
            _ = try await register(name: name)
            return try await request(method, path, body: body, auth: auth, retried: true)
        }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? String(localized: "서버에 연결할 수 없어요")
            throw ServerError(message: message, status: status)
        }
        if status == 204 || data.isEmpty, let empty = Empty() as? T { return empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "날짜 형식: \(raw)"))
        }
        return try decoder.decode(T.self, from: data)
    }
}
