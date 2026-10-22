import Foundation

private final class SentencePatternAPIProtocol: URLProtocol {
    static var payload = "{\"entries\":[]}"
    static var fail = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.path.hasPrefix("/sentence-pattern-check/") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": Self.payload]]]])
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.fail ? 503 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
func runSentencePatternChecks() async throws {
    precondition(SentencePatternDiscovery.categories.count == 14)
    let record = ReadingRecord(ocrText: "", editedText: "These small shifts help children feel capable rather than cautious.\nWhen children never get the chance to test their ideas, they miss out on experiences that build resilience and agency.", explanation: "A leads to B. This generated example is not a source.", sourceURL: "https://example.com/play", sourceApp: "Test")
    let source = ExpressionDiscovery.sources([record])[0]
    let quote = "These small shifts help children feel capable rather than cautious."
    let pattern = "[主体] help [对象] feel [状态1] rather than [状态2]."
    precondition(SentencePatternDiscovery.matchesSource(pattern: pattern, quote: quote))
    precondition(!SentencePatternDiscovery.matchesSource(pattern: "[主体] makes [对象] feel [状态].", quote: quote))
    precondition(!SentencePatternDiscovery.matchesSource(pattern: "[A]", quote: quote))
    precondition(!SentencePatternDiscovery.matchesSource(pattern: "[A] can [B]", quote: "Children can play outside."))
    precondition(SentencePatternDiscovery.originalQuote("This generated example is not a source.", record: record) == nil)
    precondition(SentencePatternDiscovery.originalQuote("small shifts help children", record: record) != nil)
    precondition(SentencePatternDiscovery.originalQuote("mall shifts help children", record: record) == nil)
    let valid: [String: Any] = ["recordID": record.id.uuidString, "quote": quote, "pattern": pattern, "category": "影响与后果", "intent": "A帮助某人形成某种感受，而非另一种", "usage": "help 后接对象和动词原形；rather than 对照两个状态，主体变化时注意 help 的词形。"]
    var invalidCategory = valid; invalidCategory["category"] = "虚构类别"
    var inventedQuote = valid; inventedQuote["quote"] = "A leads to B. This generated example is not a source."
    var inventedPattern = valid; inventedPattern["pattern"] = "[主体] leads to [结果]."
    var wrongRecord = valid; wrongRecord["recordID"] = UUID().uuidString
    let raw = String(decoding: try JSONSerialization.data(withJSONObject: ["entries": [valid, valid, invalidCategory, inventedQuote, inventedPattern, wrongRecord]]), as: UTF8.self)
    let entries = try SentencePatternDiscovery.parse(raw, source: source)
    precondition(entries.count == 1 && entries[0].quote == quote && entries[0].pattern == pattern)
    precondition(SentencePatternDiscovery.matchesSource(pattern: "[现象] driven by [原因]", quote: "It's part of a massive counter-movement against additives, driven by fears over ultra-processed foods and a desire for clean labels."))
    precondition(SentencePatternDiscovery.matchesSource(pattern: "The reason for [现象] is that [原因]", quote: "The reason for this curious exception is that manufacturers persuaded the authorities."))
    precondition(SentencePatternDiscovery.matchesSource(pattern: "[A] rather than [B]", quote: quote))
    precondition(!SentencePatternDiscovery.matchesSource(pattern: "[A] leads to [B]", quote: quote))
    let empty = try SentencePatternDiscovery.parse("{\"entries\":[]}", source: source)
    precondition(empty.isEmpty)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("birdy-syntax-check-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AppStore(storageFolder: folder, loadCredential: false)
    store.records = [record]
    store.sentencePatterns.sources[source.key] = SentencePatternCache(fingerprint: SentencePatternDiscovery.fingerprint(source), entries: entries)
    try store.persistSentencePatterns()
    precondition(store.visibleSentencePatterns.count == 1)
    store.setSentenceCategory("比较与对照", for: entries[0])
    precondition(store.visibleSentencePatterns[0].category == "比较与对照")
    let loaded = AppStore(storageFolder: folder, loadCredential: false)
    precondition(loaded.sentencePatterns.categoryOverrides[entries[0].id] == "比较与对照")
    store.undoManager.removeAllActions()
    store.undoManager.groupsByEvent = false
    store.undoManager.beginUndoGrouping()
    store.editSentencePattern(entries[0], pattern: "[A] rather than [B]", category: "比较与对照")
    store.undoManager.endUndoGrouping()
    let edited = store.visibleSentencePatterns[0]
    precondition(edited.id == entries[0].id && edited.pattern == "[A] rather than [B]")
    precondition(edited.quote == quote)
    let persistedEdit = AppStore(storageFolder: folder, loadCredential: false)
    persistedEdit.records = [record]
    precondition(persistedEdit.visibleSentencePatterns[0].pattern == edited.pattern)
    // A regenerated cache cannot discard the user's own wording.
    store.sentencePatterns.sources[source.key]?.entries = []
    precondition(store.visibleSentencePatterns[0].pattern == edited.pattern)
    store.sentencePatterns.sources[source.key]?.entries = entries
    store.undoManager.beginUndoGrouping()
    store.deleteSentencePattern(edited)
    store.undoManager.endUndoGrouping()
    precondition(store.visibleSentencePatterns.isEmpty)
    let persistedDelete = AppStore(storageFolder: folder, loadCredential: false)
    persistedDelete.records = [record]
    precondition(persistedDelete.visibleSentencePatterns.isEmpty)
    store.undoManager.undo()
    precondition(store.visibleSentencePatterns[0].pattern == edited.pattern)
    store.undoManager.undo()
    precondition(store.visibleSentencePatterns[0].pattern == pattern)
    store.undoManager.redo()
    precondition(store.visibleSentencePatterns[0].pattern == edited.pattern)
    precondition(TextFlow.prose("It is her ability to make\nthinking itself like a literary event.") == "It is her ability to make thinking itself like a literary event.")
    precondition(TextFlow.prose("  First line\r\ncontinues.\r\n  \r\nSecond\tparagraph.  ") == "First line continues.\n\nSecond paragraph.")
    precondition(TextFlow.prose("An unchanged long-term phrase — and punctuation.") == "An unchanged long-term phrase — and punctuation.")
    precondition(TextFlow.prose("One\u{2028}sentence.\u{2029}Next paragraph.") == "One sentence.\n\nNext paragraph.")
    store.records[0].editedText = "Edited text."
    precondition(store.visibleSentencePatterns.isEmpty)
    URLProtocol.registerClass(SentencePatternAPIProtocol.self)
    defer { URLProtocol.unregisterClass(SentencePatternAPIProtocol.self) }
    store.records = [record]
    store.sentencePatterns = SentencePatternState()
    store.preferences.endpoint = "http://localhost/sentence-pattern-check"
    store.apiKey = "test-only"
    SentencePatternAPIProtocol.payload = raw
    await store.refreshSentencePatterns()
    precondition(store.visibleSentencePatterns.count == 1)
    precondition(store.sentencePatternError.isEmpty && !store.refreshingSentencePatterns)
    SentencePatternAPIProtocol.fail = true
    await store.refreshSentencePatterns(force: true)
    precondition(store.visibleSentencePatterns.count == 1 && !store.sentencePatternError.isEmpty)
    let report = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("sentence-pattern-refresh-status.json"))) as! [String: Any]
    precondition(report["finished"] as? Bool == true && report["completed"] as? Int == 0)
    precondition((report["failures"] as? [String])?.count == 1)
    precondition(store.records[0].editedText == record.editedText && store.words.isEmpty)
    print("SentencePatternChecks passed: 14 categories, original quotes, grounded templates, corrections, stale cache")
}
