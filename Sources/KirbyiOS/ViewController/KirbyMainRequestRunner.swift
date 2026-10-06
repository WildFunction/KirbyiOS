import Foundation
import WildFunctionKit

/// Runs a page's main request: send, notify plugins, let the page parse, notify plugins.
///
/// Only one request is in flight; a new one cancels the previous, and cancelled requests call nothing back.
@MainActor
final class KirbyMainRequestRunner {
    private var task: Task<Void, Never>?

    /// Whether a request is in flight.
    private(set) var isLoading = false

    /// Starts a request.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - isRetry: Passed through to plugins.
    ///   - performer: Sends the request.
    ///   - pluginHost: Notified along the way. Held weakly.
    ///   - parse: The page's parsing step. Throwing reports a parsing failure.
    ///   - fail: Tells the page about a failure.
    func run(
        _ request: KirbyRequest,
        isRetry: Bool,
        performer: any KirbyRequestPerforming,
        pluginHost: KirbyPluginHost,
        parse: @escaping @MainActor (KirbyResponse) throws -> Void,
        fail: @escaping @MainActor (KirbyRequestError) -> Void
    ) {
        task?.cancel()
        isLoading = true
        pluginHost.mainRequestWillSend(request, isRetry: isRetry)

        task = Task { [weak self, weak pluginHost] in
            let outcome = await Self.perform(request, with: performer)
            // Superseded by a newer request or the page is gone: call nothing back.
            guard !Task.isCancelled, let self else { return }
            self.isLoading = false

            switch outcome {
            case .failure(.cancelled):
                return
            case .failure(let error):
                pluginHost?.mainRequestDidFail(error)
                fail(error)
            case .success(let response):
                pluginHost?.mainRequestDidReceive(response)
                do {
                    try parse(response)
                    pluginHost?.mainRequestDidParse(response)
                } catch {
                    let parsingError = KirbyRequestError.parsing(String(describing: error))
                    pluginHost?.mainRequestDidFail(parsingError)
                    fail(parsingError)
                }
            }
        }
    }

    /// Cancels the in-flight request.
    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    private static func perform(
        _ request: KirbyRequest,
        with performer: any KirbyRequestPerforming
    ) async -> Result<KirbyResponse, KirbyRequestError> {
        do {
            return .success(try await performer.perform(request))
        } catch let error as KirbyRequestError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            // A custom performer threw something unexpected; treat it as a transport failure.
            return .failure(.transport(String(describing: error)))
        }
    }
}
