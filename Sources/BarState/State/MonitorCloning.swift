import BarStateCore
import Foundation

func makeMonitorClone(from source: Monitor, name: String, order: Int) -> Monitor {
    var clone = source
    clone.id = UUID()
    clone.name = name
    clone.requestHeaders = source.requestHeaders.map { header in
        var clonedHeader = header
        clonedHeader.id = UUID()
        return clonedHeader
    }
    clone.order = order
    clone.runtime = .init()
    return clone
}
