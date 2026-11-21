import Foundation
import Testing
@testable import GarageVirtusKit

struct APIKeyStoreTests {
    let store = APIKeyStore(service: "com.rteves.GarageVirtus.tests.\(UUID().uuidString)")

    @Test func savedKeyIsReadBack() throws {
        try store.save("sk-ant-test-123")
        defer { store.delete() }
        #expect(store.read() == "sk-ant-test-123")
    }

    @Test func savingAgainReplacesKey() throws {
        try store.save("first")
        try store.save("second")
        defer { store.delete() }
        #expect(store.read() == "second")
    }

    @Test func deletedKeyIsGone() throws {
        try store.save("gone")
        store.delete()
        #expect(store.read() == nil)
    }

    @Test func missingKeyIsNil() {
        #expect(store.read() == nil)
    }
}
