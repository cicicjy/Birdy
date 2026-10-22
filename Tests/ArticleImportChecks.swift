import Foundation

@MainActor
func runArticleImportChecks() async throws {
    let source = ExtractedArticle(url: "https://example.com/essay", title: "A real title", author: "An Author", publisher: "Example", paragraphs: ["The first original paragraph explains why digital tools change expectations. It remains exactly as supplied by the source.", "The second original paragraph explains why attention still matters. Drivers should be able to find essential controls easily."], extraction: "测试全文")
    let plan = ArticleAnalysisPlan(title: "完整文章", category: "科技与社会", topics: ["数字工具"], root: 1, groups: [.init(title: "限制", main: 2, supporting: [], analysis: "第二段限定第一段的观点。")])
    let translations: [ArticleAnalysisPlan.Translation] = [.init(paragraph: 1, chinese: "第一段解释数字工具如何改变期待。", role: "论点"), .init(paragraph: 2, chinese: "第二段解释注意力仍然重要。", role: "限制")]
    let document = try plan.document(article: source, translations: translations)
    precondition(document.paragraphs.map(\.en) == source.paragraphs, "English must come from source, not model output")
    precondition(document.classification?.category == "科技与社会")
    do {
        _ = try plan.document(article: source, translations: Array(translations.prefix(1)))
        preconditionFailure("Incomplete translations cannot enter the library")
    } catch ArticleImportError.message { }
    let bad = ArticleAnalysisPlan(title: "重复", category: "科技与社会", topics: [], root: 1, groups: [.init(title: "重复", main: 1, supporting: [2], analysis: "错误")])
    do {
        _ = try bad.document(article: source, translations: translations)
        preconditionFailure("Repeated paragraph IDs cannot enter the library")
    } catch ArticleImportError.message { }

    let session = ArticleImportSession()
    session.article = source
    var completed: ArticlePracticeDocument?
    var requestCount = 0
    session.analyse(preferences: AppPreferences(), apiKey: "test-only", complete: { prompt, _, _ in
        requestCount += 1
        if prompt.contains("translations") {
            return #"{"translations":[{"paragraph":1,"chinese":"第一段完整译文。","role":"论点"},{"paragraph":2,"chinese":"第二段完整译文。","role":"限制"}]}"#
        }
        return #"{"title":"整篇文章","category":"科技与社会","topics":["数字工具"],"root":1,"groups":[{"title":"限制","main":2,"supporting":[],"analysis":"第二段限定第一段。"}]}"#
    }, save: { completed = $0 })
    await session.task?.value
    precondition(requestCount == 2 && session.error.isEmpty)
    precondition(completed?.paragraphs.map(\.en) == source.paragraphs)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("birdy-article-library-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let seed = try ArticlePracticeDocument.load(from: URL(fileURLWithPath: "Resources/ArticlePractice/article-data.json"))
    let library = ArticlePracticeLibrary(folder: folder, seed: seed)
    try library.add(document)
    precondition(library.documents.count == 2)
    let reloaded = ArticlePracticeLibrary(folder: folder, seed: seed)
    precondition(reloaded.existing(source.url + "#fragment")?.paragraphs.map(\.en) == source.paragraphs)
    try reloaded.add(document)
    precondition(reloaded.documents.count == 2, "Duplicate URLs must not create duplicate articles")
    let savedURL=folder.appendingPathComponent("article-practice.json")
    try Data("broken-library".utf8).write(to:savedURL)
    let broken = ArticlePracticeLibrary(folder: folder, seed: seed)
    precondition(!broken.error.isEmpty)
    do { try broken.add(document); preconditionFailure("Corrupt libraries must not be overwritten") } catch { }
    let retained = try String(contentsOf: savedURL, encoding: .utf8)
    precondition(retained == "broken-library")

    let html = """
    <html><head><title>Source title</title><meta name="author" content="The Author"></head><body>
    <nav><p>This navigation is not article text.</p></nav>
    <article><h1>Original heading</h1><p>First paragraph has <strong>complete</strong> wording.</p>
    <p>Second paragraph has\n    whitespace and enough original context to preserve the entire source.</p>
    <aside><p>Related story must not be imported.</p></aside>
    <p hidden>Hidden content must not be imported.</p></article>
    <script>window.unwanted=true;</script></body></html>
    """
    let extracted = try await ArticleWebReader().extract(html: html, url: URL(string: "https://example.com/essay")!)
    precondition(extracted.paragraphs == ["First paragraph has complete wording.", "Second paragraph has whitespace and enough original context to preserve the entire source."])
    precondition(extracted.author == "The Author")
    print("ArticleImportChecks passed: inert HTML extraction, complete source preservation, outline coverage, topic, persistence, duplicate URLs, corrupt library safety")
}
