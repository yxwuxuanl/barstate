import BarStateCore
import Foundation

final class ScriptServiceClient: @unchecked Sendable {
    static let serviceName = "com.barstate.BarState.ScriptService"

    func evaluate(responseData: Data, scriptBody: String) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(serviceName: Self.serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: ScriptEvaluationXPCProtocol.self)

            let replyGate = ReplyGate(continuation: continuation, connection: connection)
            connection.interruptionHandler = {
                replyGate.fail(with: MonitoringError.scriptTimeout)
            }
            connection.invalidationHandler = {
                replyGate.fail(with: MonitoringError.scriptTimeout)
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                replyGate.fail(with: MonitoringError.script(error.localizedDescription))
            }) as? ScriptEvaluationXPCProtocol else {
                replyGate.fail(with: MonitoringError.scriptServiceUnavailable)
                return
            }

            proxy.evaluate(responseJSON: responseData, scriptBody: scriptBody) { number, errorData in
                if let number {
                    replyGate.succeed(with: number.doubleValue)
                } else if let errorData,
                          let error = try? JSONDecoder().decode(
                              MonitoringError.self,
                              from: errorData
                          )
                {
                    replyGate.fail(with: error)
                } else {
                    replyGate.fail(with: MonitoringError.scriptExecutionFailed)
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
                replyGate.fail(with: MonitoringError.scriptTimeout)
            }
        }
    }
}

private final class ReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Double, Error>?
    private let connection: NSXPCConnection

    init(
        continuation: CheckedContinuation<Double, Error>,
        connection: NSXPCConnection
    ) {
        self.continuation = continuation
        self.connection = connection
    }

    func succeed(with value: Double) {
        finish(.success(value))
    }

    func fail(with error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Double, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return }
        connection.invalidate()
        continuation.resume(with: result)
    }
}
