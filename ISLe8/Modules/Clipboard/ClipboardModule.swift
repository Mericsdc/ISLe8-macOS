import SwiftUI

/// Clipboard history in its own tab of the island.
@Observable
final class ClipboardModule: IslandModule {
    let id = "clipboard"
    let service: ClipboardService
    var activity: LiveActivity? { nil }
    @ObservationIgnored var onActivityChange: (() -> Void)?

    init(service: ClipboardService) {
        self.service = service
    }

    func start() {
        service.start()
    }

    func stop() {
        service.stop()
    }
}
