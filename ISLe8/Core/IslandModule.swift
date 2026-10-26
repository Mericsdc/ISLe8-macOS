import SwiftUI

/// A feature of the island. A stopped module must hold no observers, timers or processes,
/// so that turning a feature off costs nothing.
protocol IslandModule: AnyObject {
    var id: String { get }
    /// What the module wants to show beside the notch, or nil for nothing.
    var activity: LiveActivity? { get }
    var onActivityChange: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Something the collapsed island shows in its "ears" on either side of the notch.
struct LiveActivity: Identifiable {
    let id: String
    let priority: Int
    let leading: AnyView
    let trailing: AnyView
}

/// When several activities compete for the ears, the highest priority wins.
/// Activities normally take the ears in the order set in Settings > Layout. An activity at
/// `agentApproval` or above jumps that queue: someone is waiting for an answer.
enum ActivityPriority {
    static let agentApproval = 100
    static let agents = 55
    static let media = 50
    static let timer = 40
    static let privacy = 30
}
