import Foundation
import Synchronization
import Testing
@testable import WildFunctionKit
@testable import KirbyiOS

/// Intercepts URLSession requests so nothing hits the network.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        var statusCode = 200
        var body = Data()
        var error: URLError.Code?
    }

    static let stubs = Mutex<[String: Stub]>([:])
    static let received = Mutex<[String: URLRequest]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        Self.received.withLock { $0[host] = request }
        let stub = Self.stubs.withLock { $0[host] } ?? Stub()

        if let code = stub.error {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: nil, headerFields: nil) else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("KirbyRequest")
struct KirbyRequestTests {
    @Test("GET appends sorted parameters to the existing query")
    func getAppendsSortedQuery() throws {
        let request = KirbyRequest(
            url: "https://api.example.com/demo?v=1",
            parameters: ["id": 42, "name": "a b", "flag": true, "ratio": 1.5]
        )
        let urlRequest = try request.makeURLRequest()
        #expect(urlRequest.httpMethod == "GET")
        #expect(urlRequest.url?.absoluteString == "https://api.example.com/demo?v=1&flag=true&id=42&name=a%20b&ratio=1.5")
        #expect(urlRequest.httpBody == nil)
        #expect(urlRequest.timeoutInterval == KirbyRequest.defaultTimeout)
    }

    @Test("GET without parameters keeps the URL")
    func getWithoutParameters() throws {
        let request = KirbyRequest(url: URL(string: "https://api.example.com/demo"))
        #expect(try request.makeURLRequest().url?.absoluteString == "https://api.example.com/demo")
    }

    @Test("POST encodes parameters as a JSON body with a Content-Type")
    func postEncodesJSONBody() throws {
        let request = KirbyRequest(
            url: "https://api.example.com/demo",
            method: .post,
            parameters: ["id": 42, "tags": ["a", "b"]],
            headers: ["X-Token": "t"],
            timeout: 3
        )
        let urlRequest = try request.makeURLRequest()
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.url?.absoluteString == "https://api.example.com/demo")
        #expect(urlRequest.httpBody?.wf_utf8String == #"{"id":42,"tags":["a","b"]}"#)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(urlRequest.value(forHTTPHeaderField: "X-Token") == "t")
        #expect(urlRequest.timeoutInterval == 3)
    }

    @Test("POST keeps a caller-provided Content-Type")
    func postKeepsCustomContentType() throws {
        let request = KirbyRequest(url: "https://a.example.com", method: .post, headers: ["Content-Type": "text/plain"])
        #expect(try request.makeURLRequest().value(forHTTPHeaderField: "Content-Type") == "text/plain")
    }

    @Test("Invalid URLs and disallowed schemes throw invalidRequest", arguments: ["", "   ", "ftp://example.com/a", "file:///tmp/a", "example.com/a", "javascript:alert(1)"])
    func rejectsInvalidURLs(link: String) {
        #expect(throws: KirbyRequestError.self) {
            try KirbyRequest(url: link).makeURLRequest()
        }
    }

    @Test("Unencodable parameters throw invalidRequest")
    func rejectsUnencodableParameters() {
        let nested = KirbyRequest(url: "https://a.example.com", parameters: ["list": [1, 2]])
        #expect(throws: KirbyRequestError.self) { try nested.makeURLRequest() }

        let date = KirbyRequest(url: "https://a.example.com", method: .post, parameters: ["date": Date()])
        #expect(throws: KirbyRequestError.self) { try date.makeURLRequest() }
    }

    @Test("KirbyResponse defaults")
    func responseDefaults() {
        let response = KirbyResponse(data: Data([1]))
        #expect(response.statusCode == 200)
        #expect(response.duration == .zero)
        #expect(response.data == Data([1]))
    }
}

@Suite("DefaultRequestPerformer")
struct DefaultRequestPerformerTests {
    private let performer: DefaultRequestPerformer

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        performer = DefaultRequestPerformer(configuration: configuration)
    }

    /// Each test uses its own host as the key.
    private func stub(_ host: String, _ stub: StubURLProtocol.Stub) {
        StubURLProtocol.stubs.withLock { $0[host] = stub }
    }

    @Test("2xx returns body, status and duration, and sends the parameters")
    func success() async throws {
        stub("ok.test", .init(statusCode: 201, body: Data(#"{"a":1}"#.utf8)))
        let response = try await performer.perform(KirbyRequest(url: "https://ok.test/path", parameters: ["id": 7]))

        #expect(response.statusCode == 201)
        #expect(response.data.wf_jsonDictionary?.wf_int("a") == 1)
        #expect(response.duration > .zero)
        let sent = StubURLProtocol.received.withLock { $0["ok.test"] }
        #expect(sent?.url?.query() == "id=7")
    }

    @Test("Non-2xx throws httpStatus")
    func httpError() async {
        stub("notfound.test", .init(statusCode: 404))
        await #expect(throws: KirbyRequestError.httpStatus(404)) {
            try await performer.perform(KirbyRequest(url: "https://notfound.test"))
        }
    }

    @Test("Network failures throw transport")
    func transportError() async {
        stub("offline.test", .init(error: .notConnectedToInternet))
        do {
            _ = try await performer.perform(KirbyRequest(url: "https://offline.test"))
            Issue.record("expected a transport error")
        } catch let error as KirbyRequestError {
            guard case .transport(let message) = error else {
                Issue.record("expected .transport, got \(error)")
                return
            }
            #expect(!message.isEmpty)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("Cancellation throws cancelled")
    func cancelled() async {
        stub("cancelled.test", .init(error: .cancelled))
        await #expect(throws: KirbyRequestError.cancelled) {
            try await performer.perform(KirbyRequest(url: "https://cancelled.test"))
        }
    }

    @Test("Invalid requests throw before sending")
    func invalidRequest() async {
        await #expect(throws: KirbyRequestError.self) {
            try await performer.perform(KirbyRequest(url: "ftp://nope.test"))
        }
    }

    @Test("An empty 2xx body is a success")
    func emptyBody() async throws {
        stub("empty.test", .init(statusCode: 200))
        let response = try await performer.perform(KirbyRequest(url: "https://empty.test"))
        #expect(response.statusCode == 200)
        #expect(response.data.isEmpty)
    }

    @Test("Global default performer")
    @MainActor
    func defaultPerformer() {
        #expect(KirbyRequestConfiguration.defaultPerformer is DefaultRequestPerformer)
        _ = DefaultRequestPerformer()
    }
}
