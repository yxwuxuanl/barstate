import Foundation

@objc public protocol ScriptEvaluationXPCProtocol {
    func evaluate(
        responseJSON: Data,
        scriptBody: String,
        reply: @escaping (NSNumber?, Data?) -> Void
    )
}
