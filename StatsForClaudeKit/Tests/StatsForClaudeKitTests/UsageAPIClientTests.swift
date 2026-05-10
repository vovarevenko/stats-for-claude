import Foundation
import Testing
@testable import StatsForClaudeKit

// MARK: – URLProtocol stub

/// Intercepts every request and returns whatever the current handler decides.
/// Tests assign `StubURLProtocol.handler` before each call.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private func stubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeResponse(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: UsageAPIClient.endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
}

@Suite("UsageAPIClient", .serialized)
struct UsageAPIClientTests {

    @Test("200 OK with valid JSON returns parsed UsageAPIResponse")
    func successfulFetch() async throws {
        StubURLProtocol.handler = { _ in
            let json = #"""
            {
              "five_hour": {"utilization": 42.5, "resets_at": "2026-05-10T17:00:00.000Z"},
              "seven_day": {"utilization": 73.0, "resets_at": "2026-05-17T12:00:00Z"}
            }
            """#.data(using: .utf8)!
            return (makeResponse(status: 200), json)
        }
        defer { StubURLProtocol.handler = nil }

        let client = UsageAPIClient(session: stubbedSession())
        let response = try await client.fetchUsage(token: "tok")
        #expect(response.fiveHour?.utilization == 42.5)
        #expect(response.sevenDay?.utilization == 73.0)
        #expect(response.fiveHour?.resetsAt != nil)
        #expect(response.sevenDay?.resetsAt != nil)
    }

    @Test("Authorization header carries the bearer token")
    func authHeaderSent() async throws {
        // Use a Mutex-like reference container so the handler can record the request.
        final class Box: @unchecked Sendable { var value: URLRequest? }
        let box = Box()

        StubURLProtocol.handler = { request in
            box.value = request
            return (makeResponse(status: 200), #"{"five_hour":null,"seven_day":null}"#.data(using: .utf8)!)
        }
        defer { StubURLProtocol.handler = nil }

        _ = try await UsageAPIClient(session: stubbedSession()).fetchUsage(token: "the-secret")
        let captured = try #require(box.value)
        #expect(captured.value(forHTTPHeaderField: "Authorization") == "Bearer the-secret")
        #expect(captured.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("401 surfaces as APIError.httpError(401)")
    func unauthorizedMaps() async throws {
        StubURLProtocol.handler = { _ in (makeResponse(status: 401), Data()) }
        defer { StubURLProtocol.handler = nil }

        await #expect(throws: APIError.self) {
            _ = try await UsageAPIClient(session: stubbedSession()).fetchUsage(token: "x")
        }

        do {
            _ = try await UsageAPIClient(session: stubbedSession()).fetchUsage(token: "x")
            Issue.record("expected throw")
        } catch let error as APIError {
            if case .httpError(let code) = error {
                #expect(code == 401)
            } else {
                Issue.record("wrong APIError case: \(error)")
            }
        } catch {
            Issue.record("non-APIError thrown: \(error)")
        }
    }

    @Test("500 surfaces as APIError.httpError(500)")
    func serverErrorMaps() async throws {
        StubURLProtocol.handler = { _ in (makeResponse(status: 500), Data()) }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await UsageAPIClient(session: stubbedSession()).fetchUsage(token: "x")
            Issue.record("expected throw")
        } catch let error as APIError {
            if case .httpError(let code) = error {
                #expect(code == 500)
            } else {
                Issue.record("wrong APIError case: \(error)")
            }
        } catch {
            Issue.record("non-APIError thrown: \(error)")
        }
    }

    @Test("malformed body maps to APIError.decodingFailed")
    func decodingFailureMaps() async throws {
        StubURLProtocol.handler = { _ in (makeResponse(status: 200), "garbage".data(using: .utf8)!) }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await UsageAPIClient(session: stubbedSession()).fetchUsage(token: "x")
            Issue.record("expected throw")
        } catch let error as APIError {
            if case .decodingFailed = error {} else {
                Issue.record("wrong APIError case: \(error)")
            }
        } catch {
            Issue.record("non-APIError thrown: \(error)")
        }
    }

    @Test("network error propagates")
    func networkErrorPropagates() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await UsageAPIClient(session: stubbedSession()).fetchUsage(token: "x")
            Issue.record("expected throw")
        } catch let urlError as URLError {
            #expect(urlError.code == .notConnectedToInternet)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
