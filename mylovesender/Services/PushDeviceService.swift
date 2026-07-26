import Foundation

protocol PushDeviceServiceProtocol: Sendable {
    func registerDeviceToken(_ token: Data) async throws
    func unregisterDeviceToken() async throws
}

struct PushDeviceService: PushDeviceServiceProtocol {
    func registerDeviceToken(_ token: Data) async throws {
        // APNs registration is intentionally not enabled yet.
    }

    func unregisterDeviceToken() async throws {
        // Reserved for the future push_devices backend table.
    }
}
