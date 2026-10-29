import Foundation

protocol StatementService: Sendable {
    func fetchPage(cursor: String?) async throws -> StatementPageDTO
}

enum StatementServiceError: Error, Equatable {
    case invalidEndpoint
    case nonHTTPResponse
    case httpStatus(Int)
}

struct RemoteStatementService: StatementService {
    private let endpoint: URL
    private let client: any HTTPClient

    init(endpoint: URL, client: any HTTPClient) {
        self.endpoint = endpoint
        self.client = client
    }

    func fetchPage(cursor: String?) async throws -> StatementPageDTO {
        try Task.checkCancellation()
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw StatementServiceError.invalidEndpoint
        }
        var query = (components.queryItems ?? []).filter { $0.name != "cursor" }
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw StatementServiceError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await client.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw StatementServiceError.nonHTTPResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw StatementServiceError.httpStatus(response.statusCode)
        }
        return try JSONDecoder().decode(StatementPageDTO.self, from: data)
    }
}
