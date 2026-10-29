import Foundation
import XCTest
@testable import BankingLab

final class StatementServiceTests: XCTestCase {
    func testInitialRequestUsesGETAndJSONWithoutCursor() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://example.invalid/statements?account=demo&cursor=old"))
        let client = try makeClient()
        let service = RemoteStatementService(endpoint: endpoint, client: client)

        _ = try await service.fetchPage(cursor: nil)

        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/statements?account=demo")
    }

    func testPaginationReplacesCursorAndPreservesOtherParameters() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://example.invalid/statements?account=demo&cursor=old"))
        let client = try makeClient()
        let cursor = "next/+?=& café"

        _ = try await RemoteStatementService(endpoint: endpoint, client: client).fetchPage(cursor: cursor)

        let requests = await client.requests
        let url = try XCTUnwrap(requests.first?.url)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.filter { $0.name == "cursor" }, [URLQueryItem(name: "cursor", value: cursor)])
        XCTAssertEqual(query.filter { $0.name == "account" }, [URLQueryItem(name: "account", value: "demo")])
    }

    func testDecodesPageAndPreservesExactCents() async throws {
        let json = """
        {"items":[
          {"id":"a","occurredAt":"2026-10-29T12:00:00Z","description":"Entrada","amountInCents":9223372036854775807},
          {"id":"b","occurredAt":"2026-10-28T12:00:00Z","description":"Saída","amountInCents":-9223372036854775808}
        ],"nextCursor":"opaque-token"}
        """
        let page = try await fetch(json: json)

        XCTAssertEqual(page.items, [
            StatementTransactionDTO(id: "a", occurredAt: "2026-10-29T12:00:00Z", description: "Entrada", amountInCents: .max),
            StatementTransactionDTO(id: "b", occurredAt: "2026-10-28T12:00:00Z", description: "Saída", amountInCents: .min)
        ])
        XCTAssertEqual(page.nextCursor, "opaque-token")
    }

    func testDecodesEmptyFinalPage() async throws {
        let page = try await fetch(json: #"{"items":[],"nextCursor":null}"#)

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertNil(page.nextCursor)
    }

    func testMissingOptionalCursorMeansFinalPage() async throws {
        let page = try await fetch(json: #"{"items":[]}"#)

        XCTAssertNil(page.nextCursor)
    }

    func testAcceptsSuccessfulHTTPStatus() async throws {
        let client = try makeClient(status: 201)
        let page = try await makeService(client: client).fetchPage(cursor: nil)

        XCTAssertEqual(page, StatementPageDTO(items: [], nextCursor: nil))
    }

    func testEmptySuccessfulBodyDoesNotBecomeEmptyPage() async throws {
        let client = try makeClient(status: 204, json: "")
        do {
            _ = try await makeService(client: client).fetchPage(cursor: nil)
            XCTFail("Esperava JSON mesmo em uma resposta 2xx")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testRejectsStatusBeforeDecodingBody() async throws {
        for status in [199, 300, 401, 500] {
            let client = try makeClient(status: status, json: "not JSON")
            do {
                _ = try await makeService(client: client).fetchPage(cursor: nil)
                XCTFail("Esperava erro HTTP \(status)")
            } catch {
                XCTAssertEqual(error as? StatementServiceError, .httpStatus(status))
            }
        }
    }

    func testRejectsNonHTTPResponse() async throws {
        let url = try endpoint()
        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let client = StubHTTPClient(result: .success((Data(), response)))
        do {
            _ = try await makeService(client: client).fetchPage(cursor: nil)
            XCTFail("Esperava resposta HTTP")
        } catch {
            XCTAssertEqual(error as? StatementServiceError, .nonHTTPResponse)
        }
    }

    func testRejectsMalformedOrIncompletePayloads() async throws {
        for json in ["not JSON", "{}", #"{"items":null}"#, #"{"items":[{"id":"a"}]}"#, #"{"items":[],"nextCursor":123}"#] {
            do {
                _ = try await fetch(json: json)
                XCTFail("Esperava erro de decodificação")
            } catch {
                XCTAssertTrue(error is DecodingError)
            }
        }
    }

    func testRejectsFractionalOverflowingOrStringCents() async throws {
        for amount in ["1.25", "9223372036854775808", "-9223372036854775809", "\"123\""] {
            let json = """
            {"items":[{"id":"a","occurredAt":"2026-10-29T12:00:00Z","description":"Exemplo","amountInCents":\(amount)}]}
            """
            do {
                _ = try await fetch(json: json)
                XCTFail("Esperava centavos inteiros em Int64")
            } catch {
                XCTAssertTrue(error is DecodingError)
            }
        }
    }

    func testLeavesSemanticValidationToRepository() async throws {
        let page = try await fetch(json: """
        {"items":[{"id":"","occurredAt":"invalid-date","description":"","amountInCents":0}],"nextCursor":""}
        """)

        XCTAssertEqual(page.items.first?.id, "")
        XCTAssertEqual(page.items.first?.occurredAt, "invalid-date")
        XCTAssertEqual(page.nextCursor, "")
    }

    func testPreservesTransportError() async throws {
        let client = StubHTTPClient(result: .failure(URLError(.notConnectedToInternet)))
        do {
            _ = try await makeService(client: client).fetchPage(cursor: nil)
            XCTFail("Esperava erro de transporte")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testPreservesTransportCancellation() async throws {
        let client = StubHTTPClient(result: .failure(URLError(.cancelled)))
        do {
            _ = try await makeService(client: client).fetchPage(cursor: nil)
            XCTFail("Esperava cancelamento do transporte")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
    }

    @MainActor
    func testAlreadyCancelledTaskDoesNotSendRequest() async throws {
        let client = try makeClient()
        let service = try makeService(client: client)
        let task = Task { try await service.fetchPage(cursor: nil) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Esperava cancelamento antes da requisição")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testDiscardsResponseWhenTransportIgnoresCancellation() async throws {
        let client = try makeClient(holdResponse: true)
        let service = try makeService(client: client)
        let task = Task { try await service.fetchPage(cursor: nil) }
        await client.waitUntilRequested()
        task.cancel()
        await client.releaseResponse()

        do {
            _ = try await task.value
            XCTFail("Esperava descarte da resposta após cancelamento")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func fetch(json: String) async throws -> StatementPageDTO {
        try await makeService(client: makeClient(json: json)).fetchPage(cursor: nil)
    }

    private func makeService(client: any HTTPClient) throws -> RemoteStatementService {
        RemoteStatementService(endpoint: try endpoint(), client: client)
    }

    private func endpoint() throws -> URL {
        try XCTUnwrap(URL(string: "https://example.invalid/statements"))
    }

    private func makeClient(
        status: Int = 200,
        json: String = "{\"items\":[],\"nextCursor\":null}",
        holdResponse: Bool = false
    ) throws -> StubHTTPClient {
        let response = try XCTUnwrap(HTTPURLResponse(url: endpoint(), statusCode: status, httpVersion: nil, headerFields: nil))
        return StubHTTPClient(result: .success((Data(json.utf8), response)), holdResponse: holdResponse)
    }
}

private actor StubHTTPClient: HTTPClient {
    private let result: Result<(Data, URLResponse), URLError>
    private let holdResponse: Bool
    private(set) var requests: [URLRequest] = []
    private var responseContinuation: CheckedContinuation<(Data, URLResponse), any Error>?
    private var requestContinuation: CheckedContinuation<Void, Never>?

    init(result: Result<(Data, URLResponse), URLError>, holdResponse: Bool = false) {
        self.result = result
        self.holdResponse = holdResponse
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        requestContinuation?.resume()
        requestContinuation = nil
        if holdResponse {
            return try await withCheckedThrowingContinuation { responseContinuation = $0 }
        }
        return try result.get()
    }

    func waitUntilRequested() async {
        if requests.isEmpty {
            await withCheckedContinuation { requestContinuation = $0 }
        }
    }

    func releaseResponse() {
        responseContinuation?.resume(with: result.mapError { $0 as any Error })
        responseContinuation = nil
    }
}
