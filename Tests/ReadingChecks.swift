import Foundation
import ImageIO
import Carbon
import AppKit

private final class MockAPIProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "localhost" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let valid = request.url?.path == "/mock/v1/chat/completions"
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only"
        let inner = """
        {"summary":"导读","notes":[{"quote":"quietly redrawing","kind":"rhetoric","title":"隐喻","text":"写出悄然变化"}],"vocabulary":[{"word":"quietly redrawing","meaning":"悄然重塑，强调渐进而持续的变化","example":"Anne Carson has been quietly redrawing the map of literature."}]}
        """
        let responseBody = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": inner]]]])
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 400, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct ReadingChecks {
    @MainActor static func main() async throws {
        try await runArticleImportChecks()
        try await runExpressionChecks()
        try await runSentencePatternChecks()
        let selectionBoard = NSPasteboard(name: NSPasteboard.Name("birdy-selection-check-\(UUID().uuidString)"))
        defer { selectionBoard.releaseGlobally() }
        let originalItem = NSPasteboardItem()
        originalItem.setString("旧剪贴板，不能当成选区", forType: .string)
        let originalRTF = Data("{\\rtf1 Original clipboard}".utf8)
        originalItem.setData(originalRTF, forType: .rtf)
        selectionBoard.writeObjects([originalItem])
        let before = selectionBoard.changeCount
        let missing = await TextSelectionService.readUsingCopy(pasteboard: selectionBoard, isSourceActive: { true }, copy: {})
        precondition(missing == nil && selectionBoard.changeCount == before)
        precondition(selectionBoard.string(forType: .string) == "旧剪贴板，不能当成选区")
        let copied = await TextSelectionService.readUsingCopy(pasteboard: selectionBoard, isSourceActive: { true }) {
            selectionBoard.clearContents()
            selectionBoard.setString("  These repeated messages had a lasting impact.\n ", forType: .string)
        }
        precondition(copied == "These repeated messages had a lasting impact.")
        precondition(selectionBoard.string(forType: .string) == "旧剪贴板，不能当成选区")
        precondition(selectionBoard.data(forType: .rtf) == originalRTF)
        var copyInvoked = false
        let inactive = await TextSelectionService.readUsingCopy(pasteboard: selectionBoard, isSourceActive: { false }) { copyInvoked = true }
        precondition(inactive == nil && !copyInvoked)
        let empty = await TextSelectionService.readUsingCopy(pasteboard: selectionBoard, isSourceActive: { true }) {
            selectionBoard.clearContents()
            selectionBoard.setString("  \n", forType: .string)
        }
        precondition(empty == nil && selectionBoard.data(forType: .rtf) == originalRTF)

        let source = "Anne Carson has been quietly redrawing the map of literature.\nThe map changed."
        let lines = [
            OCRLine(text: "Anne Carson has been quietly redrawing the map of literature.", x: 0.1, y: 0.5, width: 0.8, height: 0.1),
            OCRLine(text: "The map changed.", x: 0.1, y: 0.3, width: 0.3, height: 0.1)
        ]
        let paragraphLines = [
            OCRLine(text: "First line continues", x: 0.1, y: 0.75, width: 0.6, height: 0.05),
            OCRLine(text: "naturally across the screenshot", x: 0.1, y: 0.69, width: 0.7, height: 0.05),
            OCRLine(text: "A new paragraph begins here.", x: 0.1, y: 0.55, width: 0.6, height: 0.05)
        ]
        precondition(CaptureService.readableText(from: paragraphLines) == "First line continues naturally across the screenshot\n\nA new paragraph begins here.")
        precondition(ReadingAPI.rects(for: "continues naturally", lines: paragraphLines).count == 2)
        let raw = """
        {"summary":"导读","takeaway":"回看","notes":[
          {"quote":"quietly redrawing","kind":"rhetoric","title":"隐喻","text":"写出悄然变化"},
          {"quote":"map","kind":"vocabulary","title":"地图","text":"重复出现"},
          {"quote":"invented text","kind":"usage","title":"无原文","text":"不应定位"}
        ],"vocabulary":[{"word":"quietly redrawing","meaning":"悄然重塑，强调渐进持续的变化","example":"Anne Carson has been quietly redrawing the map of literature."},{"word":"Anne Carson has been quietly redrawing the map of","meaning":"不应整句入词表","example":"Anne Carson has been quietly redrawing the map of literature."}]}
        """
        let result = try ReadingAPI.parseAnalysis(raw, text: source, ocrLines: lines)
        precondition(result.notes.map(\.matched) == [true, false, false])
        precondition(result.takeaway == "回看")
        precondition(result.notes[0].screenshotRects.count == 1)
        precondition(result.notes[1].screenshotRects.isEmpty && result.notes[2].screenshotRects.isEmpty)
        let legacyAnalysis = try JSONDecoder().decode(ReadingAnalysis.self, from: Data("{\"summary\":\"旧导读\",\"notes\":[],\"vocabulary\":[]}".utf8))
        precondition(legacyAnalysis.takeaway == nil)

        let target = CaptureService.chromeTextURL(sourceURL: "https://example.com/article#section", quote: "a body of work")!
        precondition(target.absoluteString.contains("#section:~:text=a%20body%20of%20work"))

        let legacySettings = Data("{\"endpoint\":\"https://example.com/v1\",\"model\":\"legacy\",\"hotkeyKeyCode\":15,\"hotkeyModifiers\":256}".utf8)
        let migrated = try JSONDecoder().decode(AppPreferences.self, from: legacySettings)
        precondition(migrated.model == "legacy" && migrated.showWindowOnLaunch)
        precondition(migrated.hotkeyKeyCode == 15 && migrated.hotkeyModifiers == 256)
        let oldDefaultSettings = Data("{\"hotkeyKeyCode\":15,\"hotkeyModifiers\":2304}".utf8)
        let updatedHotkey = try JSONDecoder().decode(AppPreferences.self, from: oldDefaultSettings)
        precondition(updatedHotkey.hotkeyKeyCode == UInt32(kVK_ANSI_4) && updatedHotkey.hotkeyModifiers == UInt32(cmdKey))

        URLProtocol.registerClass(MockAPIProtocol.self)
        defer { URLProtocol.unregisterClass(MockAPIProtocol.self) }
        var preferences = AppPreferences()
        preferences.endpoint = "http://localhost/mock/v1"
        preferences.model = "mock-model"
        let networkResult = try await ReadingAPI.analyze(text: source, ocrLines: lines, preferences: preferences, apiKey: "test-only")
        precondition(networkResult.notes.first?.matched == true)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suibiancha-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = AppStore(storageFolder: folder, loadCredential: false)
        let record = ReadingRecord(ocrText: source, editedText: source, explanation: "导读", sourceURL: "https://example.com/article", sourceApp: "Chrome")
        first.add(record)
        first.renameRecord(record.id, to: "Carson — metaphor")
        precondition(first.records.first?.title == "Carson — metaphor")
        precondition(first.applyAnalysis(result, to: record.id, expectedText: source))
        precondition(first.records.first?.takeaway == "回看")
        precondition(first.words.isEmpty)
        first.addWord(VocabularyItem(word: "redrawing", meaning: "重新描绘", example: "Anne Carson has been quietly redrawing the map of literature.", recordID: record.id, sourceApp: "Chrome"))
        var editedWord = first.words[0]
        editedWord.meaning = "我自己的释义"
        first.updateWord(editedWord)
        precondition(first.applyAnalysis(result, to: record.id, expectedText: source))
        precondition(first.words.count == 1 && first.words[0].meaning == "我自己的释义")
        first.addWord(VocabularyItem(word: "quietly", meaning: "悄然地", example: source, recordID: record.id, sourceApp: "Chrome"))
        var relinked = first.records[0]
        relinked.sourceURL = "https://example.com/updated"
        first.update(relinked)
        precondition(first.words.allSatisfy { $0.sourceURL == relinked.sourceURL })
        let second = AppStore(storageFolder: folder, loadCredential: false)
        precondition(second.records.count == 1 && second.words.count == 2)
        precondition(second.records.first?.title == "Carson — metaphor")
        precondition(second.words.allSatisfy { $0.recordID == record.id })
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("suibiancha-check-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: backup) }
        try second.exportBackup(to: backup)
        let backupSize = try backup.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        precondition(backupSize > 0)

        if CommandLine.arguments.count > 1 {
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            let lines = try await CaptureService.recognize(image)
            let matched = try requireLine(lines.first { $0.text.contains("quietly redrawing") })
            let boxes = ReadingAPI.rects(for: "quietly redrawing", lines: lines)
            precondition(matched.wordBoxes.count > 2 && boxes.count == 1)
            precondition(boxes[0].width < matched.width)
        }
        let topic = TopicClassification(category: "美食与饮食", topics: ["食品添加剂"])
        let topicRecord = ReadingRecord(ocrText: "cake", editedText: "cake", explanation: "", sourceApp: "Test")
        second.add(topicRecord)
        let topicAnalysis = ReadingAnalysis(classification: topic, summary: "食品", notes: [], vocabulary: [])
        precondition(second.applyAnalysis(topicAnalysis, to: topicRecord.id, expectedText: "cake"))
        let topicWord = VocabularyItem(word: "cake", meaning: "蛋糕", example: "cake", recordID: topicRecord.id)
        second.addWord(topicWord)
        precondition(second.words.first { $0.id == topicWord.id }?.classification == topic)
        second.setClassification(TopicClassification(category: "科技与社会", topics: ["食品监管"]), for: topicRecord.id)
        precondition(second.applyAnalysis(topicAnalysis, to: topicRecord.id, expectedText: "cake"))
        precondition(second.records.first { $0.id == topicRecord.id }?.classification?.category == "科技与社会")
        var manualWord = second.words.first { $0.id == topicWord.id }!
        manualWord.classification = topic; manualWord.classificationIsManual = true; second.updateWord(manualWord)
        second.setClassification(TopicClassification(category: "阅读与文化", topics: []), for: topicRecord.id)
        precondition(second.words.first { $0.id == topicWord.id }?.classification == topic)
        let reloaded = AppStore(storageFolder: folder, loadCredential: false)
        precondition(reloaded.words.first { $0.id == topicWord.id }?.classificationIsManual == true)
        second.undoManager.removeAllActions()
        second.undoManager.groupsByEvent = false
        second.undoManager.beginUndoGrouping()
        second.setClassification(topic, for: topicRecord.id)
        second.undoManager.endUndoGrouping()
        precondition(second.undoManager.canUndo)
        second.undoManager.undo()
        precondition(second.records.first { $0.id == topicRecord.id }?.classification?.category == "阅读与文化")
        second.undoManager.redo()
        precondition(second.records.first { $0.id == topicRecord.id }?.classification == topic)
        second.undoManager.beginUndoGrouping()
        second.deleteRecord(topicRecord.id)
        second.undoManager.endUndoGrouping()
        precondition(!second.records.contains { $0.id == topicRecord.id })
        second.undoManager.undo()
        precondition(second.records.contains { $0.id == topicRecord.id })
        precondition(second.words.contains { $0.id == topicWord.id })
        second.undoManager.beginUndoGrouping()
        await second.restoreAutomaticClassification(for: topicRecord.id)
        second.undoManager.endUndoGrouping()
        precondition(second.records.first { $0.id == topicRecord.id }?.classificationIsManual == false)
        second.undoManager.undo()
        precondition(second.records.first { $0.id == topicRecord.id }?.classificationIsManual == true)
        let searchable = VocabularyItem(classification: TopicClassification(category: "美食与饮食", topics: ["食品添加剂"]), word: "contrasting", meaning: "形成对比", example: "sponge cakes produced from contrasting coloured segments")
        for query in ["美食", "食品添加剂", "CONTRASTING", "对比", "sponge", "coloured segments", " contrasting ", ""] {
            precondition(searchable.matchesSearch(query))
        }
        precondition(!searchable.matchesSearch("旅游"))
        let searchableRecord = ReadingRecord(classification: topic, ocrText: "original", editedText: "sponge cake", explanation: "添加剂限制", sourceApp: "Test", turns: [ChatTurn(role: "assistant", text: "补充解释")], notes: [ReadingNote(quote: "cake", kind: "usage", title: "限定", text: "法规的特例", matched: true)])
        for query in ["SPONGE", "添加剂", "法规", "补充解释", "食品", "original"] { precondition(searchableRecord.matchesSearch(query)) }
        precondition(!searchableRecord.matchesSearch("不存在的话题"))
        var practiceWord = VocabularyItem(word: "encased", meaning: "完整包裹", example: "The cake is encased in sugar paste.")
        second.undoManager.beginUndoGrouping()
        second.addWord(practiceWord)
        second.undoManager.endUndoGrouping()
        practiceWord.recitation = RecitationExercise(chinese: "蛋糕完整裹在糖膏里。", reference: practiceWord.example, target: "encased")
        second.updateWord(practiceWord, undoable: false)
        let encodedPractice = try JSONEncoder().encode(second.words.first { $0.id == practiceWord.id }!)
        let decodedPractice = try JSONDecoder().decode(VocabularyItem.self, from: encodedPractice)
        precondition(decodedPractice.recitation?.target == "encased")
        practiceWord.meaning = "被外层完全包裹"
        second.undoManager.beginUndoGrouping()
        second.updateWord(practiceWord)
        second.undoManager.endUndoGrouping()
        precondition(second.words.first { $0.id == practiceWord.id }?.recitation == nil)
        print("ReadingChecks passed")
    }
}

private func requireLine<T>(_ value: T?) throws -> T {
    guard let value else { throw APIError.badResponse("示例截图未识别出预期词句") }
    return value
}
