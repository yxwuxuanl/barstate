import Foundation

@main
enum BarStateScriptServiceMain {
    static func main() {
        let delegate = ScriptServiceDelegate()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime(delegate) {
            dispatchMain()
        }
    }
}
