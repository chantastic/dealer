import Foundation

/// Polls a file's metadata and calls `onChange` when it is created, modified, replaced, or
/// deleted. Polling (rather than a kqueue on the file descriptor) survives editors that save
/// by writing a temp file and renaming it over the original.
public final class FileChangeMonitor {
    public let url: URL
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var timer: DispatchSourceTimer?
    private var lastSignature: Signature?

    struct Signature: Equatable {
        var modified: Date?
        var size: UInt64?
        var fileNumber: UInt64?
    }

    public init(url: URL, interval: TimeInterval = 1.0, queue: DispatchQueue = .main, onChange: @escaping () -> Void) {
        self.url = url
        self.interval = interval
        self.queue = queue
        self.onChange = onChange
        self.lastSignature = Self.signature(of: url)
    }

    deinit {
        timer?.cancel()
    }

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.checkNow()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Compares the file against the last observed state; fires `onChange` and returns `true` if it differs.
    @discardableResult
    public func checkNow() -> Bool {
        let current = Self.signature(of: url)
        guard current != lastSignature else { return false }
        lastSignature = current
        onChange()
        return true
    }

    static func signature(of url: URL) -> Signature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return Signature(
            modified: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.uint64Value,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }
}
