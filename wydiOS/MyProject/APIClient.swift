import Foundation

enum APIError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }
}

extension JSONDecoder {
    static let wyd: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()
}

struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?

    private enum CodingKeys: String, CodingKey { case ok, data, error, message }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        data = try? c.decode(T.self, forKey: .data)
        if let code = try? c.decode(String.self, forKey: .error) {
            // Cloud errors look like {"error":"cloud_error","message":"table not found"}
            error = (try? c.decode(String.self, forKey: .message)) ?? code
        } else if let object = try? c.decode([String: String].self, forKey: .error) {
            error = object["message"] ?? object.values.joined(separator: ", ")
        } else {
            error = nil
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    var userToken: String?

    private init() {}

    // MARK: - Core

    private func call<T: Decodable>(_ path: String, body: [String: Any], as type: T.Type) async throws -> T {
        var request = URLRequest(url: WYDConfig.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(userToken ?? WYDConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: request)
        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder.wyd.decode(Envelope<T>.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw APIError.server("Unexpected response: \(raw.prefix(200))")
        }
        if let error = envelope.error { throw APIError.server(error) }
        guard let result = envelope.data else { throw APIError.server("Empty response from server") }
        return result
    }

    // MARK: - Auth

    func signUp(email: String, password: String) async throws -> AuthResponse {
        try await call("auth/signup", body: ["email": email, "password": password], as: AuthResponse.self)
    }

    func signIn(email: String, password: String) async throws -> AuthResponse {
        try await call("auth/signin", body: ["email": email, "password": password], as: AuthResponse.self)
    }

    // MARK: - CRUD

    func select<T: Decodable>(_ table: String, filter: [String: Any] = [:], limit: Int? = nil, as type: T.Type) async throws -> [T] {
        var body: [String: Any] = ["table": table]
        if !filter.isEmpty { body["where"] = filter }
        if let limit { body["limit"] = limit }
        return try await call("select", body: body, as: [T].self)
    }

    func insert(_ table: String, row: [String: Any]) async throws {
        var body: [String: Any] = ["table": table, "row": row]
        body["returning"] = false
        _ = try await call("insert", body: body, as: WYDIgnored.self)
    }

    func update(_ table: String, filter: [String: Any], patch: [String: Any]) async throws {
        var body: [String: Any] = ["table": table, "where": filter, "patch": patch]
        body["returning"] = false
        _ = try await call("update", body: body, as: WYDIgnored.self)
    }

    func delete(_ table: String, filter: [String: Any]) async throws {
        _ = try await call("delete", body: ["table": table, "where": filter], as: WYDIgnored.self)
    }

    // MARK: - RPC

    func rpc<T: Decodable>(_ fn: String, args: [String: Any] = [:], as type: T.Type) async throws -> [T] {
        try await call("rpc", body: ["fn": fn, "args": args], as: [T].self)
    }
}

/// Placeholder for endpoints whose `data` payload we ignore.
struct WYDIgnored: Decodable {
    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            while !array.isAtEnd { _ = try? array.decode(WYDIgnored.self) }
            return
        }
        if let object = try? decoder.container(keyedBy: AnyKey.self) {
            _ = object
            return
        }
        _ = try? decoder.singleValueContainer()
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }
}

// MARK: - ISO encoding for writes

extension Date {
    var wydISOString: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}
