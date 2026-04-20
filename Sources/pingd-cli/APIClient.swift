import AsyncHTTPClient
import Foundation
import NIOCore
import NIOFoundationCompat

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
    let httpClient: HTTPClient
    var topicPassword: String?

    private var baseURL: String { config.serverURL }

    private func request(
        method: String,
        path: String,
        body: (any Encodable)? = nil
    ) async throws -> (Data, Int) {
        var req = HTTPClientRequest(url: "\(baseURL)\(path)")
        req.method = .RAW(value: method)

        guard let token = config.token else { throw APIError.noToken }
        req.headers.add(name: "Authorization", value: "Bearer \(token)")

        if let topicPassword {
            req.headers.add(name: "X-Topic-Password", value: topicPassword)
        }

        if let body {
            req.headers.add(name: "Content-Type", value: "application/json")
            let data = try JSONEncoder().encode(body)
            req.body = .bytes(data)
        }

        let response: HTTPClientResponse
        do {
            response = try await httpClient.execute(req, timeout: .seconds(30))
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        let responseBody = try await response.body.collect(upTo: 1024 * 1024)
        let data = Data(buffer: responseBody)
        let statusCode = Int(response.status.code)

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

    func openStream(_ path: String) async throws -> HTTPClientResponse {
        var req = HTTPClientRequest(url: "\(baseURL)\(path)")
        guard let token = config.token else { throw APIError.noToken }
        req.headers.add(name: "Authorization", value: "Bearer \(token)")
        req.headers.add(name: "Accept", value: "text/event-stream")

        if let topicPassword {
            req.headers.add(name: "X-Topic-Password", value: topicPassword)
        }

        let response = try await httpClient.execute(req, timeout: .hours(24))
        guard response.status == .ok else {
            throw APIError.requestFailed(Int(response.status.code), "SSE connection failed")
        }

        return response
    }

    func consumeStream(
        _ response: HTTPClientResponse,
        onMessage: @Sendable @escaping (Data) -> Void
    ) async throws {
        var buffer = ""
        for try await chunk in response.body {
            let str = String(buffer: chunk)
            buffer += str
            let parts = buffer.split(separator: "\n\n", omittingEmptySubsequences: false)
            buffer = String(parts.last ?? "")
            for part in parts.dropLast() {
                let line = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8) {
                    onMessage(data)
                }
            }
        }
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
