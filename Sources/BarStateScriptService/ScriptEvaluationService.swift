import BarStateCore
import Darwin
import Foundation

final class ScriptEvaluationService: NSObject, ScriptEvaluationXPCProtocol {
    func evaluate(
        responseJSON: Data,
        scriptBody: String,
        reply: @escaping (NSNumber?, Data?) -> Void
    ) {
        let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        watchdog.schedule(deadline: .now() + 1)
        watchdog.setEventHandler {
            _exit(124)
        }
        watchdog.resume()

        do {
            let value = try JavaScriptEvaluator.evaluate(
                responseData: responseJSON,
                scriptBody: scriptBody
            )
            watchdog.cancel()
            reply(NSNumber(value: value), nil)
        } catch let error as MonitoringError {
            watchdog.cancel()
            reply(nil, try? JSONEncoder().encode(error))
        } catch {
            watchdog.cancel()
            reply(nil, try? JSONEncoder().encode(MonitoringError.script(error.localizedDescription)))
        }
    }
}

final class ScriptServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ScriptEvaluationXPCProtocol.self)
        connection.exportedObject = ScriptEvaluationService()
        connection.resume()
        return true
    }
}
