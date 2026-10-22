import Foundation

#if !canImport(FoundationNetworking)
/// Sends Drive uploads through a background URLSession, so iOS finishes them while the app is in the background or
/// suspended, and after the system ends it. Not after the person force-quits the app from the app switcher: iOS
/// cancels its transfers then, and the next pass starts them again.
///
/// A background session takes its bodies from files, so each one is written to `Application Support/DriveUploads`
/// first and removed when its upload ends. An upload that ends while nothing waits for it (the app was ended and
/// started again) is dropped here: the next pass finds the file on Drive by name and content (`DriveClient.existing`)
/// and records it without sending it again.
public final class DriveBackgroundTransfer: NSObject, DriveTransfer, URLSessionDataDelegate, @unchecked Sendable {
    public static let identifier = "com.tcroof.internal.drive-upload"
    /// Made at launch (`activate`), so iOS can hand over what finished while the app was closed.
    public static let shared = DriveBackgroundTransfer()

    public typealias Outcome = Result<(data: Data, status: Int), Error>

    private let lock = NSLock()
    private let folder: URL
    private var session: URLSession!
    /// Tasks started by this run of the app; others (from before a relaunch) are only cleaned up.
    private var mine: Set<Int> = []
    private var received: [Int: Data] = [:]
    private var finished: [Int: Outcome] = [:]
    private var waiting: [Int: CheckedContinuation<(data: Data, status: Int), Error>] = [:]
    private var eventsDone: (() -> Void)?
    /// The session told us its events were all delivered before iOS gave the app the handler to call.
    private var eventsFinished = false

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("DriveUploads", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var f = folder
        try? f.setResourceValues(values)
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForResource = 24 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        removeLeftovers()
    }

    /// Makes the session at launch; `shared` alone does it, this says why it is called.
    public func activate() {}

    /// The app delegate's `handleEventsForBackgroundURLSession`: iOS woke the app for this session's finished uploads.
    public func handleEvents(completion: @escaping () -> Void) {
        lock.lock()
        let already = eventsFinished
        eventsFinished = false
        if !already { eventsDone = completion }
        lock.unlock()
        if already { DispatchQueue.main.async { completion() } }
    }

    // MARK: DriveTransfer

    public func enqueue(_ request: URLRequest, body: Data) throws -> Int {
        let file = folder.appendingPathComponent(UUID().uuidString)
        #if os(iOS)
        // readable while the device is locked, as the system sends it
        try body.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try body.write(to: file, options: .atomic)
        #endif
        let task = session.uploadTask(with: request, fromFile: file)
        task.taskDescription = file.lastPathComponent
        lock.lock(); mine.insert(task.taskIdentifier); lock.unlock()
        task.resume()
        return task.taskIdentifier
    }

    public func result(_ id: Int) async throws -> (data: Data, status: Int) {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if let outcome = finished.removeValue(forKey: id) {
                lock.unlock()
                cont.resume(with: outcome)
                return
            }
            waiting[id] = cont
            lock.unlock()
        }
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); received[dataTask.taskIdentifier, default: Data()].append(data); lock.unlock()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let name = task.taskDescription { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        let id = task.taskIdentifier
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        lock.lock()
        let data = received.removeValue(forKey: id) ?? Data()
        guard mine.remove(id) != nil else { lock.unlock(); return }
        let outcome: Outcome = error.map { .failure($0) } ?? .success((data, status))
        if let cont = waiting.removeValue(forKey: id) {
            lock.unlock()
            cont.resume(with: outcome)
        } else {
            finished[id] = outcome
            lock.unlock()
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let done = eventsDone
        eventsDone = nil
        if done == nil { eventsFinished = true }
        lock.unlock()
        if let done { DispatchQueue.main.async { done() } }
    }

    /// Bodies of uploads that ended while the app was closed: files from before this launch that no task still reads
    /// (a body written since may not have its task yet).
    private func removeLeftovers() {
        let folder = folder, launched = Date()
        session.getAllTasks { tasks in
            let live = Set(tasks.compactMap(\.taskDescription))
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in files where !live.contains(name) {
                let url = folder.appendingPathComponent(name)
                let made = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
                if let made, made < launched { try? FileManager.default.removeItem(at: url) }
            }
        }
    }
}
#endif
