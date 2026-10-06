import Alamofire
import Foundation
import WildFunctionKit

/// Describes a page's main request. Subclasses supply the URL and parameters; the base class does the rest.
///
/// ```swift
/// override func mainRequest() -> KirbyRequest? {
///     KirbyRequest(url: "https://api.example.com/demo/detail", parameters: ["id": itemID])
/// }
/// ```
public struct KirbyRequest: Sendable {
    /// HTTP method.
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    /// Default timeout in seconds.
    public static let defaultTimeout: TimeInterval = 15

    /// Endpoint URL. Only `https` and `http` are allowed.
    public var url: URL?
    /// HTTP method. GET sends parameters in the query, POST as a JSON body.
    public var method: Method
    /// Parameters. GET accepts strings, numbers and booleans; POST accepts any valid JSON value.
    public var parameters: [String: any Sendable]
    /// Extra headers.
    public var headers: [String: String]
    /// Timeout in seconds.
    public var timeout: TimeInterval

    /// Creates a request from a `URL`.
    public init(
        url: URL?,
        method: Method = .get,
        parameters: [String: any Sendable] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval = KirbyRequest.defaultTimeout
    ) {
        self.url = url
        self.method = method
        self.parameters = parameters
        self.headers = headers
        self.timeout = timeout
    }

    /// Creates a request from a URL string. An unparsable string fails later in ``makeURLRequest()``.
    public init(
        url: String,
        method: Method = .get,
        parameters: [String: any Sendable] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval = KirbyRequest.defaultTimeout
    ) {
        self.init(url: url.wf_url, method: method, parameters: parameters, headers: headers, timeout: timeout)
    }

    /// Builds a `URLRequest`. Throws for an invalid URL, a disallowed scheme or unencodable parameters.
    public func makeURLRequest() throws -> URLRequest {
        guard let url, let scheme = url.scheme?.lowercased(), Self.allowedSchemes.contains(scheme) else {
            throw KirbyRequestError.invalidRequest("URL is missing or its scheme is not http(s)")
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        switch method {
        case .get:
            request.url = try urlByAppendingQuery(to: url)
        case .post:
            let body = parameters as [String: Any]
            guard let data = body.wf_jsonData() else {
                throw KirbyRequestError.invalidRequest("Parameters cannot be encoded as JSON")
            }
            request.httpBody = data
            if request.value(forHTTPHeaderField: Self.contentTypeHeader) == nil {
                request.setValue(Self.jsonContentType, forHTTPHeaderField: Self.contentTypeHeader)
            }
        }
        return request
    }

    private static let allowedSchemes: Set<String> = ["https", "http"]
    private static let contentTypeHeader = "Content-Type"
    private static let jsonContentType = "application/json"

    private func urlByAppendingQuery(to url: URL) throws -> URL {
        guard !parameters.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw KirbyRequestError.invalidRequest("URL cannot be decomposed")
        }
        // Sort by key so the same parameters always produce the same URL.
        let values = parameters as [String: Any]
        let items = try values.keys.sorted().map { key in
            guard let text = values.wf_value(key, as: String.self) else {
                throw KirbyRequestError.invalidRequest("GET parameter '\(key)' must be a string, number or boolean")
            }
            return URLQueryItem(name: key, value: text)
        }
        components.queryItems = (components.queryItems ?? []) + items
        guard let result = components.url else {
            throw KirbyRequestError.invalidRequest("Query cannot be appended to URL")
        }
        return result
    }
}

/// The response of a page's main request.
public struct KirbyResponse: Sendable {
    /// Response body.
    public let data: Data
    /// HTTP status code.
    public let statusCode: Int
    /// Time from sending the request to receiving the response.
    public let duration: Duration

    /// Creates a response. Used by custom performers and test doubles.
    public init(data: Data, statusCode: Int = 200, duration: Duration = .zero) {
        self.data = data
        self.statusCode = statusCode
        self.duration = duration
    }
}

/// Why a page's main request failed.
public enum KirbyRequestError: Error, Equatable, Sendable {
    /// The request is invalid: missing URL, disallowed scheme or unencodable parameters.
    case invalidRequest(String)
    /// Transport failure: offline, timeout, connection reset and so on.
    case transport(String)
    /// The server returned a non-2xx status code.
    case httpStatus(Int)
    /// The response arrived but the page failed to parse it.
    case parsing(String)
    /// The request was cancelled: the page went away or a newer request started.
    case cancelled
}

/// Sends requests. Apps can provide their own networking stack (signing, common parameters, host switching).
public protocol KirbyRequestPerforming: Sendable {
    /// Sends a request and returns the response. Throws ``KirbyRequestError`` on failure.
    func perform(_ request: KirbyRequest) async throws -> KirbyResponse
}

/// Default performer, backed by Alamofire. No Alamofire types leak into the public API.
public struct DefaultRequestPerformer: KirbyRequestPerforming {
    private static let successStatusCodes = 200..<300

    private let session: Session

    /// Creates a performer.
    ///
    /// - Parameter configuration: Session configuration, e.g. common headers or cache policy.
    public init(configuration: URLSessionConfiguration = .default) {
        session = Session(configuration: configuration)
    }

    public func perform(_ request: KirbyRequest) async throws -> KirbyResponse {
        let urlRequest = try request.makeURLRequest()
        let clock = ContinuousClock()
        let start = clock.now

        let response = await session.request(urlRequest)
            .validate(statusCode: Self.successStatusCodes)
            // An empty body on a 2xx response still counts as success; the page decides what it means.
            .serializingData(emptyResponseCodes: Set(Self.successStatusCodes))
            .response

        switch response.result {
        case .success(let data):
            return KirbyResponse(
                data: data,
                statusCode: response.response?.statusCode ?? Self.successStatusCodes.lowerBound,
                duration: clock.now - start
            )
        case .failure(let error):
            throw Self.map(error)
        }
    }

    private static func map(_ error: AFError) -> KirbyRequestError {
        if error.isExplicitlyCancelledError {
            return .cancelled
        }
        if let urlError = error.underlyingError as? URLError, urlError.code == .cancelled {
            return .cancelled
        }
        if case .responseValidationFailed(reason: .unacceptableStatusCode(let code)) = error {
            return .httpStatus(code)
        }
        return .transport((error.underlyingError ?? error).localizedDescription)
    }
}

/// Global configuration for main requests.
public enum KirbyRequestConfiguration {
    /// The performer every page uses by default. Replace it at launch to plug in your own networking.
    @MainActor public static var defaultPerformer: any KirbyRequestPerforming = DefaultRequestPerformer()
}
