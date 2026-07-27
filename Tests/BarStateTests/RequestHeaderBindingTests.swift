import BarStateCore
import SwiftUI
import Testing
@testable import BarState

@MainActor
struct RequestHeaderBindingTests {
    @Test func removedHeaderBindingRemainsSafeToReadAndIgnoresWrites() {
        let removedHeader = RequestHeader(name: "Authorization", value: "Bearer token")
        let remainingHeader = RequestHeader(name: "Accept", value: "application/json")
        let store = HeaderStore(headers: [removedHeader, remainingHeader])
        let headersBinding = Binding(
            get: { store.headers },
            set: { store.headers = $0 }
        )
        let removedBinding = stableRequestHeaderBinding(
            for: removedHeader,
            in: headersBinding
        )

        store.headers.removeAll { $0.id == removedHeader.id }

        #expect(removedBinding.wrappedValue == removedHeader)
        removedBinding.wrappedValue.name = "X-Removed"
        #expect(store.headers == [remainingHeader])
    }

    @Test func bindingFollowsHeaderIdentityAfterArrayIndicesChange() {
        let firstHeader = RequestHeader(name: "First", value: "1")
        let editedHeader = RequestHeader(name: "Second", value: "2")
        let store = HeaderStore(headers: [firstHeader, editedHeader])
        let headersBinding = Binding(
            get: { store.headers },
            set: { store.headers = $0 }
        )
        let editedBinding = stableRequestHeaderBinding(
            for: editedHeader,
            in: headersBinding
        )

        store.headers.removeFirst()
        editedBinding.wrappedValue.value = "updated"

        #expect(store.headers.count == 1)
        #expect(store.headers[0].id == editedHeader.id)
        #expect(store.headers[0].value == "updated")
    }
}

@MainActor
private final class HeaderStore {
    var headers: [RequestHeader]

    init(headers: [RequestHeader]) {
        self.headers = headers
    }
}
