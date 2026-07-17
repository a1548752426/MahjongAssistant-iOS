import Foundation

struct APIClient {
    enum ClientError: LocalizedError {
        case invalidURL
        case invalidResponse
        case server(Int, String)
        case noRecognizedTiles

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "服务器地址无效，请填写完整的 http:// 地址。"
            case .invalidResponse:
                return "识别服务返回了无法解析的响应。"
            case let .server(code, message):
                return "识别服务错误（\(code)）：\(message)"
            case .noRecognizedTiles:
                return "照片中没有识别到手牌，请调整拍摄角度或手动录入。"
            }
        }
    }

    func testConnection(baseURL: String) async throws {
        guard let url = normalizedBaseURL(baseURL) else { throw ClientError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<500).contains(http.statusCode) else {
            throw ClientError.server(http.statusCode, "无法访问")
        }
    }

    func startSession(baseURL: String, sessionID: String) async throws {
        let data = try await postJSON(
            baseURL: baseURL,
            path: "api/start-session",
            body: ["session_id": sessionID]
        )
        _ = try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    func endSession(baseURL: String, sessionID: String) async throws {
        _ = try await postJSON(
            baseURL: baseURL,
            path: "api/end-session",
            body: ["session_id": sessionID]
        )
    }

    func analyze(baseURL: String, sessionID: String, imageData: Data) async throws -> AnalyzeResponse {
        guard let base = normalizedBaseURL(baseURL),
              let url = URL(string: "api/analyze-hand", relativeTo: base)?.absoluteURL else {
            throw ClientError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"session_id\"\r\n\r\n")
        body.appendUTF8("\(sessionID)\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"image\"; filename=\"hand.jpg\"\r\n")
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let result = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
        guard !result.userHand.isEmpty else { throw ClientError.noRecognizedTiles }
        return result
    }

    private func postJSON(baseURL: String, path: String, body: [String: String]) async throws -> Data {
        guard let base = normalizedBaseURL(baseURL),
              let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw ClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw ClientError.server(http.statusCode, message)
        }
    }

    private func normalizedBaseURL(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.hasSuffix("/") { value += "/" }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(string.data(using: .utf8) ?? Data())
    }
}

