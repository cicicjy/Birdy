import AppKit
import Vision
import ScreenCaptureKit
import PDFKit
import Security
import ApplicationServices
import Carbon

/// Read an actual selection; never interpret the pre-existing clipboard as selected text.
@MainActor
enum TextSelectionService {
    static func selectedText(in application: NSRunningApplication) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        if let value = attribute(kAXFocusedUIElementAttribute, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() {
            let focused = value as! AXUIElement
            var budget = 180
            if let text = selectedText(in: focused, budget: &budget) { return text }
        }
        if let value = attribute(kAXFocusedWindowAttribute, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() {
            let window = value as! AXUIElement
            var budget = 300
            if let text = selectedText(in: window, budget: &budget) { return text }
        }
        // Target only the original reader. Copy works even when a browser does not expose AXSelectedText.
        let isSourceActive = { NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier }
        guard isSourceActive() else { return nil }
        return await readUsingCopy(pasteboard: .general, isSourceActive: isSourceActive) {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.postToPid(application.processIdentifier)
            up.postToPid(application.processIdentifier)
        }
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func selectedText(in element: AXUIElement, budget: inout Int, depth: Int = 0) -> String? {
        guard budget > 0, depth < 12 else { return nil }
        budget -= 1
        if let text = attribute(kAXSelectedTextAttribute, of: element) as? String {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        if let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] {
            for child in children {
                if let text = selectedText(in: child, budget: &budget, depth: depth + 1) { return text }
            }
        }
        return nil
    }

    static func readUsingCopy(pasteboard: NSPasteboard, isSourceActive: () -> Bool,
                              copy: () -> Void) async -> String? {
        guard isSourceActive() else { return nil }
        let previousItems = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let previousCount = pasteboard.changeCount
        copy()
        for _ in 0..<16 {
            guard isSourceActive(), !Task.isCancelled else { return nil }
            if pasteboard.changeCount != previousCount {
                let copiedCount = pasteboard.changeCount
                let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
                // Restore every previous format and item; do not overwrite a subsequent clipboard change.
                if pasteboard.changeCount == copiedCount {
                    pasteboard.clearContents()
                    let restored = previousItems.map { values in
                        let item = NSPasteboardItem()
                        for (type, data) in values { item.setData(data, forType: type) }
                        return item
                    }
                    if !restored.isEmpty { pasteboard.writeObjects(restored) }
                }
                return text?.isEmpty == false ? text : nil
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return nil }
        }
        return nil
    }
}

enum CaptureService {
    static func readableText(from lines: [OCRLine]) -> String {
        guard let first = lines.first else { return "" }
        var result = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
        for pair in zip(lines, lines.dropFirst()) {
            let previous = pair.0
            let current = pair.1
            let separator = separator(between: previous, and: current)
            result += separator + current.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func separator(between previous: OCRLine, and current: OCRLine) -> String {
        let verticalGap = max(0, previous.y - (current.y + current.height))
        let typicalLineHeight = (previous.height + current.height) / 2
        return verticalGap > max(0.012, typicalLineHeight * 0.8) ? "\n\n" : " "
    }

    static func recognize(_ image: CGImage) async throws -> [OCRLine] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[OCRLine], Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { result -> OCRLine? in
                    guard let candidate = result.topCandidates(1).first else { return nil }
                    let text = candidate.string
                    let box = result.boundingBox
                    let wordBoxes = Self.wordBoxes(candidate)
                    return OCRLine(text: text, x: box.minX, y: box.minY, width: box.width, height: box.height, wordBoxes: wordBoxes)
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            do { try VNImageRequestHandler(cgImage: image).perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }

    private static func wordBoxes(_ candidate: VNRecognizedText) -> [OCRWordBox] {
        let text = candidate.string
        let pattern = try? NSRegularExpression(pattern: "\\S+")
        return (pattern?.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) ?? []).compactMap { match in
            guard let range = Range(match.range, in: text), let box = try? candidate.boundingBox(for: range)?.boundingBox else { return nil }
            return OCRWordBox(start: text.distance(from: text.startIndex, to: range.lowerBound),
                              end: text.distance(from: text.startIndex, to: range.upperBound),
                              x: box.minX, y: box.minY, width: box.width, height: box.height)
        }
    }

    static func captureDisplay(in rect: CGRect) async throws -> CGImage {
        if #available(macOS 15.2, *) { return try await SCScreenshotManager.captureImage(in: rect) }
        throw APIError.badResponse("区域截图需要 macOS 15.2 或更新版本")
    }

    static func chromeURL() -> String? {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.google.Chrome" }) else { return nil }
        let script = NSAppleScript(source: "tell application \"Google Chrome\" to get URL of active tab of front window")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }

    static func chromeTextURL(sourceURL: String, quote: String?) -> URL? {
        guard let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else { return nil }
        guard let quote = quote?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty,
              ["http", "https"].contains(scheme),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        // Keep an existing section anchor while adding Chrome's text-fragment directive.
        let anchor = (parts.percentEncodedFragment ?? "").components(separatedBy: ":~:text=").first ?? ""
        let allowed = CharacterSet.urlFragmentAllowed.subtracting(CharacterSet(charactersIn: "&,=#"))
        let encoded = quote.addingPercentEncoding(withAllowedCharacters: allowed) ?? quote
        parts.percentEncodedFragment = anchor + ":~:text=" + encoded
        return parts.url ?? url
    }
}

enum ReadingAPI {
    static func complete(prompt: String, history: [ChatTurn] = [], preferences: AppPreferences, apiKey: String) async throws -> String {
        guard let base = URL(string: preferences.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"),
              let host = base.host?.lowercased(),
              base.scheme?.lowercased() == "https" || (base.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw APIError.badEndpoint
        }
        guard !apiKey.isEmpty else { throw APIError.missingKey }
        var request = URLRequest(url: base)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var messages: [[String: String]] = [["role": "system", "content": "你是一位严谨、细腻的英文 close reading 老师。你的目标不是复述或罗列术语，而是让读者看见具体语言选择怎样组织意思。每条分析都以原文证据为起点：先准确说明词句在本段里的意思，再指出真正起作用的词语、搭配、句法、语气、对照、重复或意象，解释它如何改变语义、节奏、立场或读者感受。把观察和解释连起来；仅在原文确实支持时才谈隐含意义。区分文本事实与审慎推断，不猜作者心理，不补造截图外背景。只保留有学习价值的表达，不为了显得深刻拆解普通词或堆砌文学术语；分析深度和数量随文本而定。"]]
        messages += history.map { ["role": $0.role, "content": $0.text] }
        messages.append(["role": "user", "content": prompt])
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": preferences.model, "messages": messages, "temperature": 0.3])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse("无效响应") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.badResponse("HTTP \(http.statusCode)：\(body.prefix(500))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw APIError.badResponse("响应格式中没有 choices[0].message.content") }
        return content
    }

    static var classificationInstructions: String {
        "自动按内容话题分类。classification 格式为 {\"category\":\"一个主主题\",\"topics\":[\"具体话题\"]}。主主题只能从以下选择：" + TopicClassification.categories.joined(separator: "、") + "。具体话题用简短中文，最多2个，优先使用稳定通用名称，例如食品添加剂、食品监管、跑步、职业选择、文学、旅游、服饰。根据段落实际内容而非语言分析术语分类；蛋糕添加剂限制应归为美食与饮食 / 食品添加剂，不因出现蛋糕就归为烘焙。内容不足时 category 用待分类，topics 为空。"
    }
    static func classify(text: String, preferences: AppPreferences, apiKey: String) async throws -> TopicClassification {
        let raw = try await complete(prompt: classificationInstructions + "只返回 classification 对象本身的 JSON，不要围栏。原文：\n" + text, preferences: preferences, apiKey: apiKey)
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else { throw APIError.badResponse("未返回话题分类") }
        return normalizeClassification(try JSONDecoder().decode(TopicClassification.self, from: Data(raw[start...end].utf8)))
    }
    static func normalizeClassification(_ topic: TopicClassification) -> TopicClassification {
        let category = topic.category.trimmingCharacters(in: .whitespacesAndNewlines)
        var topics: [String] = []
        for value in topic.topics {
            let value = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            if !value.isEmpty && value != category && !topics.contains(value) { topics.append(value) }
        }
        return TopicClassification(category: TopicClassification.categories.contains(category) ? category : "待分类", topics: Array(topics.prefix(1)))
    }

    static func analyze(text: String, ocrLines: [OCRLine] = [], preferences: AppPreferences, apiKey: String) async throws -> ReadingAnalysis {
        let prompt = "请为这段截图做中文 close reading，严格输出 JSON，不要 markdown 代码围栏，结构为 {\"summary\":\"一句阅读线索，约30-50字\",\"notes\":[{\"quote\":\"原文中逐字引用且尽量唯一的短语/句子\",\"kind\":\"grammar|vocabulary|usage|tone|rhetoric\",\"title\":\"简短指出值得观察的语言动作\",\"text\":\"分段讲解语境意思、写法和与普通表达的对比，通常3-4句\",\"phonetic\":\"仅 kind=vocabulary 时填写目标词/短语的英式 IPA，其他类型留空\"}],\"takeaway\":\"一句回看，约30-50字\",\"vocabulary\":[{\"word\":\"值得积累的短语或搭配，最多5个词\",\"phonetic\":\"英式 IPA，无法确定时留空\",\"meaning\":\"此处意思和必要用法\",\"example\":\"来自原文的完整语境\"}]}。\n批注要求：先确认原文意思，再挑真正值得学的表达；保留必要的句法、语法、用词、语气讲解，标题准确但避免名词堆叠。每条先解释此处意思，再说明语言机制。必须给出一个自然、意思尽量接近的普通英文表达作对照，明确标为“普通说法”，解释原文相较之下具体改变了什么（限定范围、强调焦点、强度、语域、节奏或意象），最后用一句简短的使用提示帮助用户迁移。普通说法不是引文，不得放进 quote。语义并不等价时明确指出差别，不宣称原文永远更高级或更好；普通表达更适合日常语境时说明。text 使用换行区分意思、对比和使用提示，避免一整块密集文字，不重复引文、导读或同一解释。避免长篇复述、同义反复和堆术语。分析必须指出可见的词语、搭配、语序、对照、重复、限定或指代，并说明它怎样推动本段意思；泛泛说“强调”“更生动”不算分析。优先保留最有价值、彼此不重复的几处，通常1-3处即可，也可以为空；不得为凑数拆解普通词句。批注筛选同样以 IELTS 7 为基准：基础连接词、普通二选一的 or、常规 and/by、显而易见的修饰关系和只是在翻译句意的内容不得单独成卡；仅当它们有特殊歧义、反常用法或承担关键修辞时才分析。每个候选先判断是否能带来用户不易自行发现的理解或可迁移表达；普通结构若对比没有实质差异可省略，不要硬造优势；词汇本身若有不熟悉的具体含义、形状、质感或画面感，仍值得解读，不必强求修辞优势。比如 jam or spreading jelly 中 or 的普通选择义不值得讲解。宁可只讲透一两处，也不要填满卡片。quote 必须是 OCR 原文连续子串，尽量唯一并按原文顺序排列。仅在 vocabulary 类批注上给目标词/短语加音标，不给整句标注；使用英式 IPA 并用 / / 包围，不确定时留空。截图外背景、作者心理或意图没有可靠依据时不要推断；OCR 有断裂则降低判断强度。\n词汇筛选：用户英语水平约 IELTS 7，默认认识常见日常词和基础语法。词汇表收值得主动复习的高级/少见义项、可迁移的学术或文学搭配、语义细差，以及描述形状、质感、动作或画面的具体词。不能因句法简单而跳过这类词：例如 encased 表示被外层完整包裹，应说明与 covered/coated 的差别；chequered 在蛋糕语境指交错方格图案，应区别于泛泛的 patterned，并避免误套“经历曲折”的义项。不收人名、常见基础词、整句、普通语法结构或仅为分析而引用的片段。通常0-3条，宁可为空；word 必须是原文连续短语且不超过5个词。批注和词汇表分工：批注解释写法作用，词汇表只留可迁移的表达。\n截图范围内 OCR 原文：\n" + text
        let raw = try await complete(prompt: classificationInstructions + "在下面的精读 JSON 顶层额外加入 classification 字段。\n" + prompt, preferences: preferences, apiKey: apiKey)
        return try parseAnalysis(raw, text: text, ocrLines: ocrLines)
    }

    static func parseAnalysis(_ raw: String, text: String, ocrLines: [OCRLine] = []) throws -> ReadingAnalysis {
        let jsonText: String
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") { jsonText = String(raw[start...end]) }
        else { throw APIError.badResponse("模型未返回可解析的 JSON 批注") }
        let decoded = try JSONDecoder().decode(ReadingAnalysis.self, from: Data(jsonText.utf8))
        let notes = decoded.notes.map { note in
            let matches = text.occurrences(of: note.quote)
            var n = note; n.matched = !note.quote.isEmpty && matches.count == 1
            n.screenshotRects = n.matched ? Self.rects(for: note.quote, lines: ocrLines) : []
            return n
        }
        return ReadingAnalysis(classification: decoded.classification.map(normalizeClassification), summary: decoded.summary, notes: notes, vocabulary: decoded.vocabulary, takeaway: decoded.takeaway)
    }

    static func rects(for quote: String, lines: [OCRLine]) -> [ScreenshotRect] {
        guard !lines.isEmpty else { return [] }
        var cursor = 0
        // Match the paragraph text shown to the reader, while retaining offsets into each OCR line.
        let full = CaptureService.readableText(from: lines)
        guard let range = full.occurrences(of: quote).first, full.occurrences(of: quote).count == 1 else { return [] }
        let start = full.distance(from: full.startIndex, to: range.lowerBound)
        let end = full.distance(from: full.startIndex, to: range.upperBound)
        var result: [ScreenshotRect] = []
        for (index, line) in lines.enumerated() {
            let lineStart = cursor; let lineEnd = cursor + line.text.count
            if start < lineEnd && end > lineStart {
                let localStart = max(start, lineStart) - lineStart
                let localEnd = min(end, lineEnd) - lineStart
                let boxes = line.wordBoxes.filter { $0.end > localStart && $0.start < localEnd }
                if boxes.isEmpty {
                    result.append(ScreenshotRect(x: line.x, y: line.y, width: line.width, height: line.height))
                } else {
                    let minX = boxes.map(\.x).min() ?? line.x
                    let minY = boxes.map(\.y).min() ?? line.y
                    let maxX = boxes.map { $0.x + $0.width }.max() ?? (line.x + line.width)
                    let maxY = boxes.map { $0.y + $0.height }.max() ?? (line.y + line.height)
                    result.append(ScreenshotRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
                }
            }
            cursor = lineEnd
            if index + 1 < lines.count {
                cursor += CaptureService.separator(between: line, and: lines[index + 1]).count
            }
        }
        return result
    }
}

private extension String {
    func occurrences(of fragment: String) -> [Range<String.Index>] {
        guard !fragment.isEmpty else { return [] }
        var found: [Range<String.Index>] = []; var cursor = startIndex
        while cursor < endIndex, let range = range(of: fragment, range: cursor..<endIndex) {
            found.append(range); cursor = index(after: range.lowerBound)
        }
        return found
    }
}

enum APIError: LocalizedError {
    case badEndpoint, missingKey, badResponse(String)
    var errorDescription: String? {
        switch self { case .badEndpoint: return "API 地址需要是 HTTPS；本机测试可用 localhost"; case .missingKey: return "请先在设置中填写 API Key"; case .badResponse(let message): return message }
    }
}

@MainActor
final class PDFWindowController {
    private var window: NSWindow?
    private var pdfView: PDFView?
    func open(url: URL, page: Int? = nil, quote: String? = nil, anchor: PDFAnchor? = nil) {
        let document = PDFDocument(url: url)
        guard let document else { return }
        let view = PDFView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        view.document = document; view.autoScales = true
        if let page, page > 0, let target = document.page(at: min(page - 1, document.pageCount - 1)) {
            if let anchor, anchor.page == page,
               let selection = target.selection(for: CGRect(x: anchor.x, y: anchor.y, width: anchor.width, height: anchor.height)) {
                selection.color = .systemYellow; view.go(to: selection); view.setCurrentSelection(selection, animate: true)
            } else if let quote, let range = target.string?.range(of: quote, options: .caseInsensitive),
               let selection = target.selection(for: NSRange(range, in: target.string ?? "")) {
                selection.color = .systemYellow; view.go(to: selection); view.setCurrentSelection(selection, animate: true)
            } else { view.go(to: target) }
        }
        let w = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = url.lastPathComponent; w.contentView = view; w.center(); w.makeKeyAndOrderFront(nil); window = w; pdfView = view
    }
    func selectedAnchor() -> PDFAnchor? {
        guard let view = pdfView, let selection = view.currentSelection, let page = selection.pages.first,
              let document = view.document, let text = selection.string, !text.isEmpty else { return nil }
        let rect = selection.bounds(for: page)
        return PDFAnchor(page: document.index(for: page) + 1, quote: text,
                         x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}
