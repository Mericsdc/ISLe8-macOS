import SwiftUI
import UniformTypeIdentifiers

/// The file shelf: drop files on the notch to keep them at hand, drag them out again, or
/// send them with AirDrop. Also announces files received by AirDrop.
@Observable
final class ShelfModule: IslandModule {
    let id = "shelf"
    let store: ShelfStore
    var activity: LiveActivity? { nil }

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored var onFileDragNearIsland: ((Bool) -> Void)?
    @ObservationIgnored var onAirDropReceived: ((Int) -> Void)?
    @ObservationIgnored var islandGeometry: (() -> NotchGeometry?)? {
        didSet { dragWatcher.islandGeometry = islandGeometry }
    }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let dragWatcher = FileDragWatcher()
    @ObservationIgnored private let airDropReceiver = AirDropReceiver()
    @ObservationIgnored private var isStarted = false

    init(settings: SettingsStore, store: ShelfStore) {
        self.settings = settings
        self.store = store
        dragWatcher.onNearIslandChange = { [weak self] near in self?.onFileDragNearIsland?(near) }
        airDropReceiver.onReceive = { [weak self] urls in self?.received(urls) }
        settings.onModuleSettingsChange { [weak self] in self?.applySettings() }
    }

    func start() {
        isStarted = true
        dragWatcher.start()
        applySettings()
    }

    func stop() {
        isStarted = false
        dragWatcher.stop()
        airDropReceiver.stop()
    }

    func add(_ urls: [URL]) {
        store.add(urls, copy: settings.copyFilesToShelf)
    }

    func zip(_ item: ShelfItem) {
        Task {
            if let zipped = await ShelfActions.zip(item.url, fallbackFolder: store.filesFolder) {
                store.add([zipped], copy: false)
            } else {
                NSSound.beep()
            }
        }
    }

    func convert(_ item: ShelfItem, to type: UTType) {
        Task {
            if let converted = await ShelfActions.convert(item.url, to: type, fallbackFolder: store.filesFolder) {
                store.add([converted], copy: false)
            } else {
                NSSound.beep()
            }
        }
    }

    private func applySettings() {
        if isStarted && settings.showAirDropReceived {
            airDropReceiver.start()
        } else {
            airDropReceiver.stop()
        }
    }

    private func received(_ urls: [URL]) {
        store.add(urls, copy: false)
        onAirDropReceived?(urls.count)
    }
}
