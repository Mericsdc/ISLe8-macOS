// Ported from LimitBar LRX (based on dancik/limitbar, MIT License).
// Original LimitBar © 2026 dancik; the license text ships as Resources/LimitBar-LICENSE.txt.
// The data layer (CLI discovery and trust checks, isolated spawning, the Seatbelt profile,
// fetchers, scheduling, cache and power reading) follows LimitBar's Sources/LimitBar; the
// vendor marks come from simple-icons (CC0).

import AppKit
import Foundation

/// How much of each AI service's usage limit is used, asked through each vendor's official CLI
/// (`codex`, `claude`, `agy`). No token, cookie or keychain item is ever opened: sign-in stays
/// inside the CLI. Codex and agy run in a Seatbelt sandbox, claude with its own isolation
/// flags; every CLI gets an allowlisted environment and a private empty working directory,
/// runs under a hard deadline in its own process group, and is killed with that group.
///
/// Cadence: Codex and Antigravity are asked every 5 min with the island closed, every minute
/// while it is open, and every 15 min in saver mode or Low Power Mode. Claude's CLI runs at
/// most every 20 min, and at most every 30 s on a manual refresh. Codex's own session logs are
/// read for free whenever Codex writes them. Nothing runs while the Mac sleeps, failures back
/// off up to 30 min, and all CLI work happens on a serial background queue.
@Observable
final class UsageModule: IslandModule {
    let id = "usage"
    var activity: LiveActivity? { nil }
    @ObservationIgnored var onActivityChange: (() -> Void)?

    /// One per enabled vendor whose CLI is installed or that has data, in UsageVendor.allCases order.
    private(set) var snapshots: [UsageSnapshot] = []
    /// True while a CLI is being asked; the free checks between those don't count.
    private(set) var isRefreshing = false
    /// Watts going into the Mac from the adapter; nil on battery or when the sensor has nothing.
    private(set) var adapterWatts: Double?
    /// Fired once per window each time it crosses 90 % used (not again until it drops below and crosses again).
    @ObservationIgnored var onLimitWarning: ((UsageSnapshot, UsageWindow) -> Void)?

    /// Stored as the vendors turned off, so a vendor added later starts out on.
    var enabledVendors: Set<UsageVendor> = Set(UsageVendor.allCases) {
        didSet {
            guard enabledVendors != oldValue else { return }
            let disabled = UsageVendor.allCases.filter { !enabledVendors.contains($0) }.map(\.rawValue)
            defaults.set(disabled, forKey: Key.disabledVendors)
            reconcile()
        }
    }

    /// Codex and Antigravity every 15 min instead of 5, and slower checks of the free sources.
    /// On by default: at the 5-minute cadence the CLIs alone cost about 0.3 % CPU.
    var saverMode = true {
        didSet {
            guard saverMode != oldValue else { return }
            defaults.set(saverMode, forKey: Key.saverMode)
            configureMonitoring()
        }
    }

    /// Off: nothing runs at all, and the snapshots are cleared.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Key.isEnabled)
            reconcile()
        }
    }

    private enum Key {
        static let disabledVendors = "usage.disabledVendors"
        static let saverMode = "usage.saverMode"
        static let isEnabled = "usage.isEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let queue = DispatchQueue(label: "com.lrxe8.isle8.usage.fetch", qos: .utility)
    /// Codex log reads and cache writes, so a slow CLI never holds them up.
    @ObservationIgnored private let localQueue = DispatchQueue(label: "com.lrxe8.isle8.usage.local", qos: .utility)
    @ObservationIgnored private let fetcher = UsageFetcher()
    @ObservationIgnored private let power = UsagePowerMonitor()
    @ObservationIgnored private var watcher: UsageFileWatcher?

    @ObservationIgnored private var snaps: [UsageVendor: UsageSnapshot] = [:]
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var asleep = false
    @ObservationIgnored private var cacheLoaded = false
    /// What `reconcile` last left running, to tell what has just started.
    @ObservationIgnored private var runningVendors: Set<UsageVendor> = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var jobs: [UsageVendor: UsageCancellation] = [:]
    @ObservationIgnored private var askingVendors: Set<UsageVendor> = []
    @ObservationIgnored private var lastPoll: [UsageVendor: Date] = [:]
    @ObservationIgnored private var failures: [UsageVendor: Int] = [:]
    @ObservationIgnored private var localRead: Task<Void, Never>?
    @ObservationIgnored private var lastLocalRead = Date.distantPast
    @ObservationIgnored private var localJob: UsageCancellation?
    /// Windows at 90 % or more that have already been warned about.
    @ObservationIgnored private var hotWindows: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let disabled = Set((defaults.stringArray(forKey: Key.disabledVendors) ?? []).compactMap(UsageVendor.init(rawValue:)))
        enabledVendors = Set(UsageVendor.allCases).subtracting(disabled)
        saverMode = defaults.object(forKey: Key.saverMode) as? Bool ?? true
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        power.onChange = { [weak self] snapshot in
            guard let self, self.adapterWatts != snapshot.adapterWatts else { return }
            self.adapterWatts = snapshot.adapterWatts
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        reconcile()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        reconcile()
    }

    /// The island opened or closed. Open asks Codex and Antigravity every minute (Limitbar's
    /// panel-open rule) and is the only time watts are read, so a closed island costs nothing;
    /// opening reads them right away.
    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        configurePower()
        if visible { poll(olderThan: 30) }
    }

    /// A manual refresh: every vendor now, but Claude's `/usage` and Codex's app-server at most
    /// every 30 s (Limitbar's forced-refresh rules).
    func refresh() {
        poll(force: true)
    }

    // MARK: State

    private var isActive: Bool { isStarted && isEnabled }
    private var isRunning: Bool { isActive && !asleep && !enabledVendors.isEmpty }
    private var lowEnergy: Bool { saverMode || ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// Brings observers, jobs, timers and watchers in line with the settings, and asks the
    /// vendors that have just started running.
    private func reconcile() {
        if isActive {
            observeSystem()
            loadCacheOnce()
        } else {
            stopObservingSystem()
            asleep = false
            if adapterWatts != nil { adapterWatts = nil }
        }
        if !isEnabled { clear() }
        let running = isRunning ? enabledVendors : []
        if running.isEmpty {
            cancelAll()
        } else {
            for vendor in UsageVendor.allCases where !running.contains(vendor) { cancel(vendor) }
        }
        let previous = runningVendors
        runningVendors = running
        configureMonitoring()
        publish()
        guard !running.isEmpty else { return }
        if previous.isEmpty {
            poll(force: true)
        } else {
            for vendor in UsageVendor.allCases where running.contains(vendor) && !previous.contains(vendor) {
                schedule(vendor, force: true)
            }
        }
    }

    private func setSleeping(_ sleeping: Bool) {
        guard asleep != sleeping else { return }
        asleep = sleeping
        reconcile()
    }

    private func clear() {
        snaps.removeAll()
        hotWindows.removeAll()
        lastPoll.removeAll()
        failures.removeAll()
        cacheLoaded = false
    }

    private func observeSystem() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let sleep = workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSleeping(true) }
        }
        let wake = workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSleeping(false) }
        }
        // Low Power Mode slows everything down the way saver mode does.
        let powerState = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureMonitoring() }
        }
        observers = [(workspace, sleep), (workspace, wake), (NotificationCenter.default, powerState)]
    }

    private func stopObservingSystem() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    // MARK: Timers and watchers

    private func configureMonitoring() {
        configurePower()
        timer?.invalidate()
        timer = nil
        guard isRunning else {
            watcher?.stop()
            watcher = nil
            localRead?.cancel()
            localRead = nil
            return
        }
        rebuildWatchers()
        // Only cheap checks run on this tick; each live query keeps its own minimum interval.
        timer = Timer.scheduledTimer(withTimeInterval: lowEnergy ? 60 : 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rebuildWatchers()
                self.poll()
            }
        }
        timer?.tolerance = lowEnergy ? 15 : 5
    }

    /// Watts are read only while the island is open, so a closed island costs nothing.
    private func configurePower() {
        power.configure(enabled: isActive && !asleep && isVisible, economy: lowEnergy)
    }

    private func rebuildWatchers() {
        guard isRunning, enabledVendors.contains(.codex) else {
            watcher?.stop()
            watcher = nil
            return
        }
        if watcher == nil {
            watcher = UsageFileWatcher { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.scheduleLocalRead() }
                }
            }
        }
        watcher?.watch(codexRoot: fetcher.codexLogs.root)
    }

    /// Codex writes a log several times in a row; read once it has settled, at most every 2 s.
    private func scheduleLocalRead() {
        guard isRunning else { return }
        localRead?.cancel()
        let delay = max(0.6, 2 - Date().timeIntervalSince(lastLocalRead))
        localRead = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.lastLocalRead = Date()
            self.rebuildWatchers()
            self.readLocalSources()
        }
    }

    private func readLocalSources() {
        guard localJob == nil, enabledVendors.contains(.codex),
              ![UsageState.missing, .untrusted, .signedOut].contains(snaps[.codex]?.state ?? .ok)
        else { return }
        let token = UsageCancellation()
        localJob = token
        let logs = fetcher.codexLogs
        localQueue.async { [weak self] in
            guard !token.isCancelled else { return }
            let value = logs.latest()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.localReadFinished(value, token) }
            }
        }
    }

    private func localReadFinished(_ value: UsageSnapshot?, _ token: UsageCancellation) {
        guard localJob === token else { return }
        localJob = nil
        guard !token.isCancelled, isRunning, enabledVendors.contains(.codex), var value else { return }
        let previous = snaps[.codex]
        guard ![UsageState.signedOut, .untrusted, .missing].contains(previous?.state ?? .ok),
              let time = value.measuredAt, time > (previous?.measuredAt ?? .distantPast)
        else { return }
        if value.plan.isEmpty { value.plan = previous?.plan ?? "" }
        value.notes = previous?.notes ?? []
        apply(.codex, value)
    }

    // MARK: Polling

    /// `olderThan` re-checks the free sources sooner (opening the island); a live query keeps
    /// its own minimum interval either way.
    private func poll(force: Bool = false, olderThan: TimeInterval? = nil) {
        guard isRunning else { return }
        for vendor in UsageVendor.allCases where enabledVendors.contains(vendor) && jobs[vendor] == nil {
            let age = Date().timeIntervalSince(lastPoll[vendor] ?? .distantPast)
            if !force {
                let state = snaps[vendor]?.state
                if state == .missing || state == .untrusted || state == .signedOut {
                    if age < 5 * 60 { continue }
                } else if let count = failures[vendor], count > 0,
                          age < UsagePollingPolicy.retryDelay(failures: count) {
                    continue
                }
                // Antigravity has no free source: every poll is a live query.
                let interval = vendor == .gemini ? remoteInterval(vendor) : (olderThan ?? (lowEnergy ? 60 : 30))
                if age < interval { continue }
            }
            schedule(vendor, force: force)
        }
    }

    private func remoteInterval(_ vendor: UsageVendor) -> TimeInterval {
        if vendor != .claude && isVisible && !lowEnergy { return 60 }
        return UsagePollingPolicy.remoteInterval(vendor, economy: lowEnergy)
    }

    private func schedule(_ vendor: UsageVendor, force: Bool) {
        guard isRunning, enabledVendors.contains(vendor), jobs[vendor] == nil else { return }
        let token = UsageCancellation()
        jobs[vendor] = token
        let previous = snaps[vendor]
        let remoteGap = remoteInterval(vendor)
        let fetcher = fetcher
        queue.async { [weak self] in
            guard !token.isCancelled else { return }
            let snapshot = UsageCLI.withCancellation(token) {
                fetcher.fetch(vendor, previous: previous, force: force, remoteGap: remoteGap) {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.markAsking(vendor, token) }
                    }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finished(vendor, token, snapshot) }
            }
        }
    }

    private func markAsking(_ vendor: UsageVendor, _ token: UsageCancellation) {
        guard jobs[vendor] === token else { return }
        askingVendors.insert(vendor)
        updateRefreshing()
    }

    private func finished(_ vendor: UsageVendor, _ token: UsageCancellation, _ snapshot: UsageSnapshot?) {
        guard jobs[vendor] === token else { return }
        jobs.removeValue(forKey: vendor)
        askingVendors.remove(vendor)
        updateRefreshing()
        guard !token.isCancelled, isRunning, enabledVendors.contains(vendor) else { return }
        lastPoll[vendor] = Date()
        guard let snapshot else { return }
        failures[vendor] = snapshot.state == .failed ? (failures[vendor] ?? 0) + 1 : 0
        apply(vendor, snapshot)
    }

    private func cancel(_ vendor: UsageVendor) {
        jobs.removeValue(forKey: vendor)?.cancel()
        askingVendors.remove(vendor)
        if vendor == .codex {
            localJob?.cancel()
            localJob = nil
        }
        updateRefreshing()
    }

    private func cancelAll() {
        for vendor in UsageVendor.allCases { cancel(vendor) }
        localJob?.cancel()
        localJob = nil
        localRead?.cancel()
        localRead = nil
    }

    private func updateRefreshing() {
        let refreshing = !askingVendors.isEmpty
        if isRefreshing != refreshing { isRefreshing = refreshing }
    }

    // MARK: Snapshots

    private func apply(_ vendor: UsageVendor, _ incoming: UsageSnapshot) {
        var next = incoming
        // A failure keeps the last numbers beside its error.
        if next.state == .failed, let old = snaps[vendor], next.windows.isEmpty, !old.windows.isEmpty {
            next.windows = old.windows
            next.bar = old.bar
            next.measuredAt = old.measuredAt
            next.source = old.source
            next.plan = old.plan
        }
        if next.plan.isEmpty && next.state == .ok { next.plan = snaps[vendor]?.plan ?? "" }
        guard snaps[vendor] != next else { return }
        snaps[vendor] = next
        saveCache()
        publish()
        warnAboutHotWindows(next)
    }

    private func publish() {
        let visible = UsageVendor.allCases.compactMap { vendor -> UsageSnapshot? in
            guard enabledVendors.contains(vendor), let snapshot = snaps[vendor],
                  snapshot.state != .missing || !snapshot.windows.isEmpty
            else { return nil }
            return snapshot
        }
        if visible != snapshots { snapshots = visible }
    }

    private func warnAboutHotWindows(_ snapshot: UsageSnapshot) {
        let prefix = "\(snapshot.vendor.rawValue)|"
        if snapshot.state == .ok {
            // A window that is gone can warn again once it comes back.
            let current = Set(snapshot.windows.map { prefix + $0.id })
            hotWindows = hotWindows.filter { !$0.hasPrefix(prefix) || current.contains($0) }
        }
        for window in snapshot.windows {
            let key = prefix + window.id
            if window.isHot {
                if hotWindows.insert(key).inserted { onLimitWarning?(snapshot, window) }
            } else {
                hotWindows.remove(key)
            }
        }
    }

    // MARK: Cache

    private func loadCacheOnce() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: UsageCache.stateFile)) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cached = try? decoder.decode([String: UsageSnapshot].self, from: data) else { return }
        for (key, value) in cached {
            guard let vendor = UsageVendor(rawValue: key), value.vendor == vendor, snaps[vendor] == nil else { continue }
            snaps[vendor] = value
            // Already over 90 % last time: that was warned about then.
            for window in value.windows where window.isHot {
                hotWindows.insert("\(vendor.rawValue)|\(window.id)")
            }
        }
    }

    private func saveCache() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let all = Dictionary(uniqueKeysWithValues: snaps.map { ($0.key.rawValue, $0.value) })
        guard let data = try? encoder.encode(all) else { return }
        localQueue.async {
            UsageCache.write(data, to: UsageCache.stateFile)
        }
    }
}
