import AppKit
import SwiftUI
import Carbon
import ApplicationServices

@main
struct SuibianchaEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AppStore()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var capturePanel: NSPanel?
    private var readingPanel: NSPanel?
    private var readingClickMonitor: Any?
    private var localReadingClickMonitor: Any?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private let pdfController = PDFWindowController()
    private var lastSourceApp = "屏幕"
    private var lastSourceApplication: NSRunningApplication?
    private var didPromptForAccessibility = false
    private var readingSelection = false
    private var isPreparingCapture = false
    private var presentingMainWindow = false
    private var sawInitialActivation = false
    private var windowIntent = WindowPresentationIntent()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 Birdy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤回", action: #selector(BirdyWindow.undo(_:)), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: #selector(BirdyWindow.redo(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(); editItem.submenu = editMenu; mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = BlueWrenIcon.menuBarImage()
        statusItem.button?.image?.accessibilityDescription = "Birdy，蓝色小鸟"
        let menu = NSMenu()
        menu.addItem(withTitle: "选词 / 框选精读  ⌘4", action: #selector(beginCapture), keyEquivalent: "")
        menu.addItem(withTitle: "截图框选精读", action: #selector(beginScreenshotCapture), keyEquivalent: "")
        menu.addItem(withTitle: "打开单词本", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Birdy", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        lastSourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "屏幕"
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastSourceApplication = frontmost
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor [weak self] in
                self?.lastSourceApp = app.localizedName ?? "屏幕"
                self?.lastSourceApplication = app
            }
        }
        if CommandLine.arguments.contains("--refresh-existing-analysis") {
            Task { await store.refreshExistingAnalyses() }
        } else { Task { await store.classifyExistingRecords() } }
        Task { await store.refreshExpressionLinks(force: CommandLine.arguments.contains("--refresh-expression-links")) }
        Task { await store.refreshSentencePatterns(force: CommandLine.arguments.contains("--refresh-sentence-patterns")) }
        registerHotKey()
        if store.preferences.showWindowOnLaunch { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !sawInitialActivation {
            sawInitialActivation = true
            if !store.preferences.showWindowOnLaunch && window == nil { return }
        }
        restoreMainWindowIfNeeded()
    }
    func applicationDidUnhide(_ notification: Notification) { restoreMainWindowIfNeeded() }

    private func restoreMainWindowIfNeeded() {
        // Capture panels are non-activating. A real app activation (Dock / app switcher)
        // expresses intent to return, even if a capture or OCR task is still pending.
        guard !presentingMainWindow else { return }
        if window == nil || window?.isVisible == false || window?.isMiniaturized == true {
            showWindow()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "birdy" && url.host?.lowercased() == "close-reading" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let text = components.queryItems?.first(where: { $0.name == "text" })?.value,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let sourceURL = components.queryItems?.first(where: { $0.name == "url" })?.value
            let validSourceURL: String? = {
                guard let sourceURL, let candidate = URLComponents(string: sourceURL),
                      ["http", "https"].contains(candidate.scheme?.lowercased() ?? "") else { return nil }
                return sourceURL
            }()
            Task { await processSelectedText(text, sourceApp: "Google Chrome", sourceURL: validSourceURL) }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc func showWindow() {
        guard !presentingMainWindow else { return }
        presentingMainWindow = true
        defer { presentingMainWindow = false }
        windowIntent.requestMainWindow()
        isPreparingCapture = false
        dismissCapturePanel()
        dismissReadingPanel()
        if window == nil {
            let root = RootView(store: store, capture: { [weak self] in self?.beginScreenshotCapture() }, openPDF: { [weak self] url, page, quote, anchor in self?.pdfController.open(url: url, page: page, quote: quote, anchor: anchor) }, selectedPDFAnchor: { [weak self] in self?.pdfController.selectedAnchor() })
            let w = BirdyWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.store = store
            w.title = "Birdy"; w.contentView = NSHostingView(rootView: root); w.center(); w.isReleasedWhenClosed = false; window = w
        }
        NSApp.unhide(nil)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        if window?.styleMask.contains(.fullScreen) == false { window?.collectionBehavior.insert(.moveToActiveSpace) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func beginCapture() {
        guard !readingSelection else { return }
        dismissReadingPanel()
        guard let source = currentReadingApplication(), source.processIdentifier != getpid() else {
            store.statusMessage = "请先在网页或 PDF 中选中文字，再按 ⌘4"
            showWindow()
            return
        }
        guard AXIsProcessTrusted() else {
            if !didPromptForAccessibility {
                didPromptForAccessibility = true
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            store.statusMessage = "需要辅助功能权限才能读取选中文字；请在系统设置中允许 Birdy 后重试 ⌘4"
            showWindow()
            return
        }
        readingSelection = true
        let selectionIntent = windowIntent.captureToken
        Task {
            defer { readingSelection = false }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != source.processIdentifier {
                source.activate(options: [])
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else {
                store.statusMessage = "请回到原网页，选中文字后再按 ⌘4"
                return
            }
            let selectedText = await TextSelectionService.selectedText(in: source)
            guard windowIntent.canPresentCapture(selectionIntent) else { return }
            guard let selectedText else {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else {
                    store.statusMessage = "阅读应用已切换，请回到原网页后重试 ⌘4"
                    return
                }
                beginScreenshotCapture()
                return
            }
            let sourceApp = source.localizedName ?? lastSourceApp
            let sourceURL = sourceApp.localizedCaseInsensitiveContains("Chrome") ? CaptureService.chromeURL() : nil
            await processSelectedText(selectedText, sourceApp: sourceApp, sourceURL: sourceURL)
        }
    }

    @objc func beginScreenshotCapture() {
        dismissReadingPanel()
        let source = currentReadingApplication()
        let sourceApp = source?.localizedName ?? lastSourceApp
        let sourceURL = sourceApp.localizedCaseInsensitiveContains("Chrome") ? CaptureService.chromeURL() : nil
        guard capturePanel == nil, !isPreparingCapture else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            store.statusMessage = "Birdy 尚未获得屏幕录制权限；请在系统设置中允许，随后重启 Birdy"
            showWindow()
            let alert = NSAlert()
            alert.messageText = "需要屏幕录制权限"
            alert.informativeText = "之前的截图只拍到了桌面壁纸。请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 Birdy，然后重启应用。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        guard let screen = NSScreen.screens.first else { store.statusMessage = "找不到屏幕"; return }
        let union = NSScreen.screens.dropFirst().reduce(screen.frame) { $0.union($1.frame) }
        guard let source else { store.statusMessage = "找不到阅读应用，请先点一下网页或 PDF"; return }
        store.statusMessage = "正在固定当前阅读画面…"
        let captureIntent = windowIntent.captureToken
        isPreparingCapture = true
        Task {
            defer { if windowIntent.canPresentCapture(captureIntent) { isPreparingCapture = false } }
            do {
                guard windowIntent.canPresentCapture(captureIntent) else { return }
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
                    window?.orderOut(nil)
                    source.activate(options: [])
                    try await Task.sleep(for: .milliseconds(300))
                }
                guard windowIntent.canPresentCapture(captureIntent) else { return }
                let image = try await CaptureService.captureDisplay(in: union)
                guard windowIntent.canPresentCapture(captureIntent) else { return }
                window?.orderOut(nil)
                let picker = RegionPicker(frame: union, image: image) { [weak self] croppedImage, selectionRect, _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.dismissCapturePanel()
                        await self.capture(croppedImage, sourceApp: sourceApp, sourceURL: sourceURL, selectionRect: selectionRect, intent: captureIntent)
                    }
                } cancel: { [weak self] in
                    self?.dismissCapturePanel()
                }
                let overlay = CapturePanel(contentRect: union, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                overlay.level = .screenSaver; overlay.backgroundColor = .clear; overlay.isOpaque = false; overlay.hasShadow = false
                overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; overlay.contentView = picker
                capturePanel = overlay
                overlay.makeKeyAndOrderFront(nil)
            } catch {
                guard windowIntent.canPresentCapture(captureIntent) else { return }
                store.statusMessage = "无法固定阅读窗口：\(error.localizedDescription)"
                showWindow()
            }
        }
    }

    @objc func closeReadingSelection(_ pasteboard: NSPasteboard, userData: String,
                                     error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let selectedText = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !selectedText.isEmpty else {
            error.pointee = "请先在原文中选中一段文字，再使用 Birdy 精读。" as NSString
            return
        }
        let source = currentReadingApplication()
        let sourceApp = source?.localizedName ?? lastSourceApp
        let sourceURL = sourceApp.localizedCaseInsensitiveContains("Chrome") ? CaptureService.chromeURL() : nil
        Task { await processSelectedText(selectedText, sourceApp: sourceApp, sourceURL: sourceURL) }
    }

    private func currentReadingApplication() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier { return lastSourceApplication }
        return frontmost ?? lastSourceApplication
    }

    private func processSelectedText(_ selectedText: String, sourceApp: String, sourceURL: String?) async {
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var record = ReadingRecord(ocrText: text, editedText: text, explanation: "",
                                   sourceURL: sourceURL, sourceApp: sourceApp)
        record.title = String(text.prefix(42))
        store.add(record)
        store.statusMessage = "已接收选中文字，正在生成精读…"
        presentCapturedRecord(record, near: CGRect(origin: NSEvent.mouseLocation, size: .zero))
        await analyzeAutomatically(record)
    }

    private func dismissCapturePanel() {
        capturePanel?.orderOut(nil)
        capturePanel = nil
    }

    private func capture(_ image: CGImage, sourceApp: String, sourceURL: String?, selectionRect: CGRect, intent: UInt64) async {
        store.statusMessage = "正在截取和识别…"
        do {
            let ocrLines = try await CaptureService.recognize(image)
            let text = CaptureService.readableText(from: ocrLines)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.statusMessage = "未识别到文字，可以在记录中手动编辑" }
            var record = ReadingRecord(ocrText: text, editedText: text, explanation: "", sourceURL: sourceURL, sourceApp: sourceApp, ocrLines: ocrLines)
            record.screenshotPath = try store.saveScreenshot(image, for: record.id)
            store.add(record)
            if windowIntent.canPresentCapture(intent) {
                presentCapturedRecord(record, near: selectionRect)
            } else {
                // A Dock/reopen request wins over a late OCR result. Keep the record without hiding the window again.
                store.selectedRecordID = record.id
                store.requestedReadingID = record.id
            }
            store.statusMessage = text.isEmpty ? "未识别到文字，可以在记录中手动编辑" : "识别完成，正在生成精读…"
            if !text.isEmpty, !store.apiKey.isEmpty { Task { await analyzeAutomatically(record) } }

        } catch {
            store.statusMessage = "截屏或识别失败：\(error.localizedDescription)。请到系统设置的隐私与安全性中允许屏幕录制，再重启 Birdy。"
            showWindow()
        }
    }

    private func analyzeAutomatically(_ original: ReadingRecord, inline: Bool = false, anchor: CGRect? = nil) async {
        store.analyzingRecordIDs.insert(original.id)
        defer { store.analyzingRecordIDs.remove(original.id) }
        store.statusMessage = "正在生成中文精读和批注…"
        do {
            let analysis = try await ReadingAPI.analyze(text: original.editedText, ocrLines: original.ocrLines, preferences: store.preferences, apiKey: store.apiKey)
            guard store.applyAnalysis(analysis, to: original.id, expectedText: original.editedText) else {
                store.statusMessage = "识别文本已修改，请在记录中重新生成精读"
                return
            }
            store.statusMessage = "精读完成，批注和原文词条已保存"
        } catch {
            store.statusMessage = "自动精读失败：\(error.localizedDescription)；可在记录中重试"
            if inline, let anchor {
                presentReadingPanel(recordID: original.id, near: anchor, errorMessage: error.localizedDescription,
                                    retry: { [weak self] in
                    guard let self else { return }
                    Task { await self.analyzeAutomatically(original, inline: true, anchor: anchor) }
                })
            }
        }
    }

    private func dismissReadingPanel() {
        readingPanel?.orderOut(nil)
        readingPanel = nil
        if let readingClickMonitor { NSEvent.removeMonitor(readingClickMonitor) }
        if let localReadingClickMonitor { NSEvent.removeMonitor(localReadingClickMonitor) }
        readingClickMonitor = nil
        localReadingClickMonitor = nil
    }

    private func presentCapturedRecord(_ record: ReadingRecord, near anchor: CGRect) {
        let isWeb = record.sourceURL != nil || ["Chrome", "Safari", "Firefox", "Edge", "Arc", "Brave"]
            .contains { record.sourceApp.localizedCaseInsensitiveContains($0) }
        if isWeb {
            window?.orderOut(nil)
            lastSourceApplication?.activate(options: [])
            presentReadingPanel(recordID: record.id, near: anchor)
        } else {
            store.requestedReadingID = record.id
            showWindow()
        }
    }

    private func presentReadingPanel(recordID: UUID, near anchor: CGRect,
                                     errorMessage: String? = nil, retry: (() -> Void)? = nil) {
        let width: CGFloat = 370
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let height = min(570, visible.height - 28)
        let rightX = anchor.maxX + 14
        let leftX = anchor.minX - width - 14
        let x: CGFloat
        if rightX + width <= visible.maxX - 12 { x = rightX }
        else if leftX >= visible.minX + 12 { x = leftX }
        else { x = visible.maxX - width - 12 }
        let y = min(max(anchor.midY - height / 2, visible.minY + 12), visible.maxY - height - 12)
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let panel = readingPanel ?? ReadingOverlayPanel(contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.setFrame(frame, display: true)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: InlineReadingOverlay(store: store, recordID: recordID,
            errorMessage: errorMessage, retry: retry, close: { [weak self] in self?.dismissReadingPanel() })
            .allowsHitTesting(false)
            .overlay {
                Button { [weak self] in
                    guard let self else { return }
                    self.store.selectedRecordID = recordID
                    self.store.requestedReadingID = recordID
                    self.showWindow()
                } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("在 Birdy 中打开这条精读")
            })
        dismissReadingPanel()
        readingPanel = panel
        panel.orderFrontRegardless()
        readingClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissReadingPanel() }
        }
        localReadingClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.window !== self?.readingPanel { self?.dismissReadingPanel() }
            }
            return event
        }
    }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in delegate.beginCapture() }
            return noErr
        }, 1, &spec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &hotKeyHandler)
        let prefs = store.preferences
        let id = EventHotKeyID(signature: OSType(0x53554942), id: 1)
        let result = RegisterEventHotKey(prefs.hotkeyKeyCode, prefs.hotkeyModifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { store.statusMessage = "⌘4 快捷键注册失败（错误码 \(result)）；请检查是否被其他应用占用" }
    }
}

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class ReadingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class RegionPicker: NSView {
    private let image: CGImage
    private let completion: (CGImage, CGRect, RegionPicker) -> Void
    private let cancel: () -> Void
    private var start: NSPoint?
    private var current: NSPoint?
    private var selectedBox: CGRect?
    private var isProcessing = false
    init(frame: CGRect, image: CGImage, completion: @escaping (CGImage, CGRect, RegionPicker) -> Void, cancel: @escaping () -> Void) {
        self.image = image; self.completion = completion; self.cancel = cancel; super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    private var imageRect: CGRect {
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    private func clamped(_ point: NSPoint) -> NSPoint {
        NSPoint(x: min(max(point.x, imageRect.minX), imageRect.maxX),
                y: min(max(point.y, imageRect.minY), imageRect.maxY))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.78).setFill(); bounds.fill()
        NSImage(cgImage: image, size: imageRect.size).draw(in: imageRect)
        NSColor.black.withAlphaComponent(0.5).setFill(); NSBezierPath(rect: imageRect).fill()
        if let start, let current {
            let box = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(start.x-current.x), height: abs(start.y-current.y))
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: box).addClip()
            NSImage(cgImage: image, size: imageRect.size).draw(in: imageRect)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.systemBlue.setStroke(); let path = NSBezierPath(rect: box); path.lineWidth = 2; path.stroke()
        }
        let instruction = isProcessing ? "正在识别所选片段 · Esc 取消" : "在当前阅读窗口的截图上拖动框选 · Esc 取消"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white]
        instruction.draw(at: NSPoint(x: 24, y: bounds.height - 40), withAttributes: attrs)
    }
    override func mouseDown(with event: NSEvent) {
        guard !isProcessing else { return }
        start = clamped(convert(event.locationInWindow, from: nil)); current = start; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) { current = clamped(convert(event.locationInWindow, from: nil)); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        current = clamped(convert(event.locationInWindow, from: nil))
        guard let start, let current else { return }
        let local = CGRect(x: min(start.x,current.x), y: min(start.y,current.y), width: abs(start.x-current.x), height: abs(start.y-current.y))
        guard local.width > 8, local.height > 8 else { cancel(); return }
        let display = imageRect
        selectedBox = local
        isProcessing = true
        needsDisplay = true
        let pixelRect = CGRect(x: (local.minX - display.minX) / display.width * CGFloat(image.width),
                               y: (display.maxY - local.maxY) / display.height * CGFloat(image.height),
                               width: local.width / display.width * CGFloat(image.width),
                               height: local.height / display.height * CGFloat(image.height)).integral
        guard let cropped = image.cropping(to: pixelRect) else { cancel(); return }
        let screenRect = CGRect(x: frame.minX + (local.minX - display.minX) / display.width * frame.width,
                                y: frame.minY + (local.minY - display.minY) / display.height * frame.height,
                                width: local.width / display.width * frame.width,
                                height: local.height / display.height * frame.height)
        completion(cropped, screenRect, self)
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { cancel() } else { super.keyDown(with: event) } }

}

final class BirdyWindow: NSWindow {
    weak var store: AppStore?
    override var undoManager: UndoManager? { store?.undoManager }
    @objc func undo(_ sender: Any?) { store?.undoManager.undo() }
    @objc func redo(_ sender: Any?) { store?.undoManager.redo() }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(BirdyWindow.undo(_:)) { return store?.undoManager.canUndo == true }
        if menuItem.action == #selector(BirdyWindow.redo(_:)) { return store?.undoManager.canRedo == true }
        return super.validateMenuItem(menuItem)
    }
}
