import Foundation

private final class ExpressionAPIProtocol: URLProtocol {
    static var payload = "{\"links\":[]}"
    static var fail = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.path.hasPrefix("/expression-check/") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let content = ExpressionAPIProtocol.payload
        let data = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.fail ? 503 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
func runExpressionChecks() async throws {
    let first = ReadingRecord(ocrText: "", editedText: "Childhood trauma can leave scars. These experiences can persist.", explanation: "invented alternative", sourceURL: "https://example.com/article?utm_source=reader#part", sourceApp: "Test")
    let second = ReadingRecord(ocrText: "", editedText: "Our research examines adverse\nchildhood experiences.", explanation: "", sourceURL: "https://example.com/article", sourceApp: "Test")
    let different = ReadingRecord(ocrText: "", editedText: "psychological trauma", explanation: "", sourceURL: "https://example.com/other", sourceApp: "Test")
    let sources = ExpressionDiscovery.sources([first, second, different])
    precondition(sources.count == 2)
    let source = sources.first { $0.records.count == 2 }!
    precondition(ExpressionDiscovery.sourceKey(first) == ExpressionDiscovery.sourceKey(second))
    var queryArticle = second; queryArticle.sourceURL = "https://example.com/article?id=2"
    precondition(ExpressionDiscovery.sourceKey(queryArticle) != source.key)
    precondition(ExpressionDiscovery.evidence(phrase: "adverse childhood experiences", recordID: second.id, records: source.records)?.phrase == "adverse\nchildhood experiences")
    precondition(ExpressionDiscovery.evidence(phrase: "hood trauma", recordID: first.id, records: source.records) == nil)
    precondition(ExpressionDiscovery.evidence(phrase: "invented alternative", recordID: first.id, records: source.records) == nil)
    for phrase in ["these experiences", "such adversity", "it", "this issue", "the latter", "THESE\nexperiences"] {
        precondition(!ExpressionDiscovery.isLexical(phrase))
    }
    for phrase in ["childhood trauma", "adverse childhood experiences", "encased", "a body of work"] {
        precondition(ExpressionDiscovery.isLexical(phrase))
    }
    func draft(_ phrase: String, _ id: UUID, kind: String = "contextualRephrase") -> [String: Any] {
        ["first": ["recordID": first.id.uuidString, "phrase": "childhood trauma"], "second": ["recordID": id.uuidString, "phrase": phrase], "kind": kind, "distinction": "都围绕童年不利经历，前者强调创伤，后者强调经历，不能无条件互换。"]
    }
    let drafts = [draft("adverse childhood experiences", second.id), draft("these experiences", first.id), draft("invented alternative", first.id), draft("psychological trauma", different.id), draft("scars", first.id, kind: "sameTopic"), draft("childhood trauma", first.id), draft("adverse childhood experiences", second.id)]
    let raw = String(decoding: try JSONSerialization.data(withJSONObject: ["links": drafts]), as: UTF8.self)
    let links = try ExpressionDiscovery.parse(raw, source: source)
    precondition(links.count == 1)
    precondition(links[0].first.quote == "Childhood trauma can leave scars.")
    precondition(links[0].second.quote.contains("Our research"))
    let empty = try ExpressionDiscovery.parse("{\"links\":[]}", source: source)
    precondition(empty.isEmpty)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("birdy-expression-check-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AppStore(storageFolder: folder, loadCredential: false)
    store.records = [first, second]
    store.expressionLinks.sources[source.key] = ExpressionSourceCache(fingerprint: source.fingerprint, links: links)
    try store.persistExpressionLinks()
    precondition(store.visibleExpressionLinks.count == 1)
    let word = VocabularyItem(word: "childhood trauma", meaning: "", example: "", recordID: first.id)
    precondition(store.links(for: store.expressionEvidence(for: word)!).count == 1)
    store.dismissExpressionLink(links[0])
    precondition(store.visibleExpressionLinks.isEmpty)
    let reloaded = AppStore(storageFolder: folder, loadCredential: false)
    precondition(reloaded.expressionLinks.dismissed.contains(links[0].id))
    store.expressionLinks.dismissed = []
    store.records[0].editedText = "Changed excerpt."
    precondition(store.visibleExpressionLinks.isEmpty)
    store.records = [first]
    precondition(store.visibleExpressionLinks.isEmpty)
    URLProtocol.registerClass(ExpressionAPIProtocol.self)
    defer { URLProtocol.unregisterClass(ExpressionAPIProtocol.self) }
    store.records = [first, second]
    store.expressionLinks = ExpressionLinkState()
    store.preferences.endpoint = "http://localhost/expression-check"
    store.apiKey = "test-only"
    ExpressionAPIProtocol.payload = raw
    await store.refreshExpressionLinks()
    precondition(store.visibleExpressionLinks.count == 1)
    precondition(store.expressionLinkError.isEmpty && !store.refreshingExpressionLinks)
    let unchangedReadings = try JSONEncoder().encode(store.records)
    ExpressionAPIProtocol.fail = true
    await store.refreshExpressionLinks(force: true)
    precondition(store.visibleExpressionLinks.count == 1) // Keep the successful cache on a failed refresh.
    precondition(!store.expressionLinkError.isEmpty)
    let afterRefresh = try JSONEncoder().encode(store.records)
    // Compare decoded values because JSON key order is unspecified.
    let beforeJSON = try JSONSerialization.jsonObject(with: unchangedReadings)
    let afterJSON = try JSONSerialization.jsonObject(with: afterRefresh)
    precondition(NSDictionary(dictionary: ["r": beforeJSON]).isEqual(to: ["r": afterJSON]))
    let report = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("expression-refresh-status.json"))) as! [String: Any]
    precondition(report["finished"] as? Bool == true && report["completed"] as? Int == 0)
    precondition((report["failures"] as? [String])?.count == 1)
    print("ExpressionChecks passed: source evidence, references, boundaries, grouping, stale cache, persistence")
}
