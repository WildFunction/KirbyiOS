import Foundation
import KirbyiOS
import WFRouter
import WildFunctionKit

/// The Example has no backend, so this performer fakes the responses.
struct DemoRequestPerformer: KirbyRequestPerforming {
    private enum Mock {
        static let latency: Duration = .milliseconds(800)
        static let listCount = 30
    }

    func perform(_ request: KirbyRequest) async throws -> KirbyResponse {
        // Build the real request so invalid URLs and parameters fail the same way as in production.
        let urlRequest = try request.makeURLRequest()
        try await Task.sleep(for: Mock.latency)

        let body: [String: Any]
        switch urlRequest.url?.path() {
        case DemoAPI.detailPath:
            let id = (request.parameters as [String: Any]).wf_string("id")
            // Deliberately sloppy types (numeric id, string price) to show SafeJSON's leniency.
            body = ["id": id.wf_intValue ?? 0, "title": "Item #\(id)", "price": "19.9"]
        case DemoAPI.listPath:
            body = ["items": (1...Mock.listCount).map { ["id": $0, "title": "Item #\($0)"] }]
        default:
            throw KirbyRequestError.httpStatus(404)
        }

        guard let data = body.wf_jsonData() else {
            throw KirbyRequestError.transport("Mock response cannot be encoded")
        }
        return KirbyResponse(data: data, duration: Mock.latency)
    }
}

enum DemoAPI {
    static let host = "https://demo.wildfunction.invalid"
    static let detailPath = "/detail"
    static let listPath = "/list"
}
