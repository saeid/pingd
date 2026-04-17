import Foundation

enum APIError: Error, CustomStringConvertible {
    case noToken
    case requestFailed(Int, String)
    case networkError(String)
    case decodingError(String)

    var description: String {
        switch self {
        case .noToken: "No token configured. Server may not have started yet."
        case .requestFailed(let code, let message): "HTTP \(code): \(message)"
        case .networkError(let message): "Network error: \(message)"
        case .decodingError(let message): "Decoding error: \(message)"
        }
    }
}

struct APIClient {
    let config: CLIConfig

    private var baseURL: String { config.serverURL }

    private func request(
        method: String,
        path: String,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true
    ) async throws -> (Data, Int) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.networkError("Invalid URL: \(baseURL)\(path)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method

        if requiresAuth {
            guard let token = config.token else { throw APIError.noToken }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(statusCode, message)
        }

        return (data, statusCode)
    }

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let (data, _) = try await request(method: "GET", path: path)
        return try decode(data, as: type)
    }

    func post<T: Decodable>(_ path: String, body: any Encodable, as type: T.Type) async throws -> T {
        let (data, _) = try await request(method: "POST", path: path, body: body)
        return try decode(data, as: type)
    }

    func patch<T: Decodable>(_ path: String, body: any Encodable, as type: T.Type) async throws -> T {
        let (data, _) = try await request(method: "PATCH", path: path, body: body)
        return try decode(data, as: type)
    }

    func delete(_ path: String) async throws {
        _ = try await request(method: "DELETE", path: path)
    }

    func stream(_ path: String) async throws -> URLSession.AsyncBytes {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.networkError("Invalid URL: \(baseURL)\(path)")
        }
        var req = URLRequest(url: url)
        if let token = config.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode >= 400 {
            throw APIError.requestFailed(statusCode, "SSE connection failed")
        }
        return bytes
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}
