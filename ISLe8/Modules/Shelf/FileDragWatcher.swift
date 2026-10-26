import AppKit

/// Notices files being dragged towards the notch so the island can open as a drop target.
/// It listens only to mouse drags in other apps, so between drags it does nothing.
final class FileDragWatcher {
    var onNearIslandChange: ((Bool) -> Void)?
    var islandGeometry: (() -> NotchGeometry?)?

    private var monitors: [Any] = []
    private var dragChangeCount = 0
    private var isFileDrag = false
    private var isNear = false

    func start() {
        guard monitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        setNear(false)
    }

    private func mouseDown() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        isFileDrag = false
    }

    private func mouseDragged() {
        if !isFileDrag {
            // A drag session that carries files rewrites the drag pasteboard once.
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != dragChangeCount else { return }
            dragChangeCount = pasteboard.changeCount
            isFileDrag = pasteboard.types?.contains(.fileURL) ?? false
            guard isFileDrag else { return }
        }
        setNear(isNearIsland(NSEvent.mouseLocation))
    }

    private func mouseUp() {
        isFileDrag = false
        // Give a drop on the island a moment to land before the drop target closes.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            setNear(false)
        }
    }

    /// The zone is wider once the drop target is open, so moving onto its zones keeps it open.
    private func isNearIsland(_ point: NSPoint) -> Bool {
        guard let geometry = islandGeometry?() else { return false }
        let depth: CGFloat = isNear ? 200 : 90
        let halfWidth: CGFloat = isNear ? 300 : 260
        return point.y >= geometry.screenFrame.maxY - depth
            && point.y <= geometry.screenFrame.maxY
            && abs(point.x - geometry.notchMidX) <= halfWidth
    }

    private func setNear(_ near: Bool) {
        guard near != isNear else { return }
        isNear = near
        onNearIslandChange?(near)
    }
}
