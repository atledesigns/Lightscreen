import AppKit
import ApplicationServices
import SwiftUI

/// Runs the whole Full Page capture: find the window that was in front, make
/// sure we're allowed to drive it, auto-scroll it behind a little progress
/// card, stitch the frames into one tall image, then show a quick preview with
/// the option to keep it or redo the scroll by hand.
@MainActor
final class ScrollCaptureController {
    private let engine: CaptureEngine
    private lazy var driver = AutoScrollDriver(engine: engine)

    /// Set by the app: hand the finished tall capture on to the editor/preview.
    var onResult: ((PendingCapture) -> Void)?

    /// One full-page run at a time.
    private var inFlight = false

    // The live surfaces.
    private let recorder = ScrollRecorderModel()
    private var recorderPanel: NSPanel?
    private var resultPanel: NSPanel?
    private var manualPanel: NSPanel?
    private let manual = ManualScrollModel()

    /// Facts carried onto whatever we end up saving.
    private var sourceBundleID: String?
    private var outputMode: OutputMode = .raw

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    // MARK: - Entry point

    func begin(sourceAppBundleID: String?, outputMode: OutputMode) {
        guard !inFlight else { return }
        self.sourceBundleID = sourceAppBundleID
        self.outputMode = outputMode

        // Which window are we scrolling? Whatever was in front when ⌘⇧7 fired.
        guard let target = resolveTarget(bundleID: sourceAppBundleID) else {
            NSLog("Lightscreen: full-page capture found no window to scroll.")
            return
        }

        // Driving another app's scroll needs Accessibility permission. If we
        // don't have it yet, ask once and send the user to the right Settings
        // pane — they grant it, then re-press ⌘⇧7.
        guard ensureAccessibility() else { return }

        inFlight = true
        Task { await runAuto(target: target) }
    }

    // MARK: - The automatic pass

    private func runAuto(target: OnScreenWindow) async {
        let pid = target.ownerPID
        // Bring the target app forward so our scroll events land on it; our
        // progress card floats above without stealing its focus.
        NSRunningApplication(processIdentifier: pid)?.activate()
        try? await Task.sleep(for: .milliseconds(350))

        let cgFrame = WindowEnumerator.cgBounds(forWindowID: target.id) ?? CGRect(origin: .zero, size: target.appKitFrame.size)
        let centre = CGPoint(x: cgFrame.midX, y: cgFrame.midY)

        showRecorder(over: target.appKitFrame)

        let frames = await driver.run(
            windowID: target.id,
            windowCenterCG: centre,
            pointHeight: cgFrame.height,
            progress: { [weak self] p in self?.recorder.progress = p },
            shouldStop: { [weak self] in self?.recorder.stopRequested ?? true }
        )

        hideRecorder()

        guard let stitched = ImageStitcher.stitch(frames) else {
            NSLog("Lightscreen: full-page capture produced nothing to stitch.")
            inFlight = false
            return
        }
        showResult(stitched, target: target)
    }

    // MARK: - The result preview ("keep it / redo by hand")

    private func showResult(_ image: CGImage, target: OnScreenWindow) {
        closeResult()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        let view = ScrollResultView(
            image: nsImage,
            onUse: { [weak self] in self?.finish(with: image) },
            onRetry: { [weak self] in self?.closeResult(); self?.startManual(target: target) },
            onCancel: { [weak self] in self?.closeResult(); self?.inFlight = false }
        )
        let panel = makeCardPanel(content: view, size: NSSize(width: 460, height: 560), key: true)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        resultPanel = panel
    }

    private func finish(with image: CGImage) {
        closeResult()
        defer { inFlight = false }
        guard let png = pngData(from: image) else {
            NSLog("Lightscreen: could not encode the stitched full-page image.")
            return
        }
        let now = Date()
        let suggested = LibraryStore.suggestedFilename(for: now)
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suggested)
        try? png.write(to: tempURL)

        let pending = PendingCapture(
            pngData: png,
            image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            captureMode: .fullPage,
            outputMode: outputMode,
            sourceAppBundleID: sourceBundleID,
            capturedAt: now,
            suggestedName: suggested,
            tempURL: tempURL
        )
        onResult?(pending)
    }

    // MARK: - The manual rescue pass

    /// For pages auto-scroll can't tame: the user scrolls the window themselves
    /// and taps Snap at each step; we stitch the snaps the same way.
    private func startManual(target: OnScreenWindow) {
        NSRunningApplication(processIdentifier: target.ownerPID)?.activate()
        manual.reset()
        manual.onSnap = { [weak self] in self?.manualSnap(target: target) }
        manual.onFinish = { [weak self] in self?.manualFinish(target: target) }
        manual.onCancel = { [weak self] in self?.closeManual(); self?.inFlight = false }

        let view = ManualScrollView(model: manual)
        let panel = makeCardPanel(content: view, size: NSSize(width: 320, height: 168), key: false)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 28, y: f.midY))
        }
        panel.orderFrontRegardless()
        manualPanel = panel
    }

    private func manualSnap(target: OnScreenWindow) {
        Task {
            guard let frame = try? await engine.captureWindowCGImage(windowID: target.id) else { return }
            manual.frames.append(frame)
            manual.count = manual.frames.count
        }
    }

    private func manualFinish(target: OnScreenWindow) {
        let frames = manual.frames
        closeManual()
        guard let stitched = ImageStitcher.stitch(frames) else {
            inFlight = false
            return
        }
        showResult(stitched, target: target)
    }

    // MARK: - Recorder overlay plumbing

    private func showRecorder(over appKitFrame: CGRect) {
        recorder.progress = 0
        recorder.stopRequested = false
        let view = ScrollRecorderView(model: recorder)
        let panel = makeCardPanel(content: view, size: NSSize(width: 280, height: 92), key: false)
        // Centred horizontally on the window, tucked just below its top edge.
        let x = appKitFrame.midX - panel.frame.width / 2
        let y = appKitFrame.maxY - panel.frame.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        recorderPanel = panel
    }

    private func hideRecorder() {
        recorderPanel?.orderOut(nil)
        recorderPanel = nil
    }

    private func closeResult() {
        resultPanel?.orderOut(nil)
        resultPanel = nil
    }

    private func closeManual() {
        manualPanel?.orderOut(nil)
        manualPanel = nil
    }

    // MARK: - Helpers

    /// The window full-page should scroll: the front window of the app that was
    /// active before the picker opened, falling back to the frontmost window of
    /// anything if we can't pin the app down.
    private func resolveTarget(bundleID: String?) -> OnScreenWindow? {
        if let bundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let window = WindowEnumerator.frontmostWindow(forPID: app.processIdentifier) {
            return window
        }
        // Last resort: the topmost ordinary window that isn't ours.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let centre = NSScreen.main.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? .zero
        return WindowEnumerator.frontmostWindow(atAppKitPoint: centre, excludingPID: ownPID)
    }

    /// True if we may drive other apps. If not, prompt once and open Settings.
    private func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        NSLog("Lightscreen: full-page capture needs Accessibility. Prompted and opened System Settings.")
        return false
    }

    /// A borderless, glassy floating card hosting a SwiftUI view. Non-key cards
    /// (`key: false`) never steal focus — vital while we're scrolling another
    /// app — but their buttons still work.
    private func makeCardPanel(content: some View, size: NSSize, key: Bool) -> NSPanel {
        let panel = FloatingCardPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: key ? [.borderless] : [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = !key
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: AnyView(content))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.allowsKeyCanBecome = key
        return panel
    }

    private func pngData(from cg: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }
}

/// A borderless panel that can become key only when we ask it to (the result
/// card), so the non-activating recorder/manual cards stay out of the way.
private final class FloatingCardPanel: NSPanel {
    var allowsKeyCanBecome = true
    override var canBecomeKey: Bool { allowsKeyCanBecome }
    override var canBecomeMain: Bool { allowsKeyCanBecome }
}

// MARK: - Live models the SwiftUI cards observe

/// Drives the little progress card during auto-scroll.
@MainActor
final class ScrollRecorderModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var stopRequested = false
}

/// Backs the manual rescue card: how many snaps so far, and the buttons' jobs.
@MainActor
final class ManualScrollModel: ObservableObject {
    @Published var count = 0
    var frames: [CGImage] = []
    var onSnap: (() -> Void)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?

    func reset() {
        count = 0
        frames = []
    }
}
