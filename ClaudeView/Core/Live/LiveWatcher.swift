import Foundation
import CoreServices

/// FSEvents watcher on ~/.claude/projects: reports changed .jsonl files
/// (debounced by FSEvents latency) to a callback on a background queue.
final class LiveWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "fr.lauriat.ClaudeView.watcher", qos: .utility)
    private let rootPath: String
    private let onChange: ([URL]) -> Void

    init(rootPath: String, onChange: @escaping ([URL]) -> Void) {
        self.rootPath = rootPath
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<LiveWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let pathArray = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            let urls = pathArray.prefix(Int(count))
                .filter { $0.hasSuffix(".jsonl") }
                .map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty { watcher.onChange(urls) }
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // latency (seconds) — coalesces bursts of writes
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
