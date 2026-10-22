import Foundation
import AppKit
import Carbon
import Combine

struct RecitationExercise: Codable {
    var chinese: String
    var reference: String
    var target: String
}

struct TopicClassification: Codable, Equatable {
    static let categories = ["运动与身体", "美食与饮食", "阅读与文化", "购物与消费", "居住与日常", "旅行与城市", "关系与情绪", "学习与成长", "工作与职业", "科技与社会", "金钱与生活选择"]
    var category: String
    var topics: [String]
    var label: String { ([category] + Array(topics.prefix(1))).joined(separator: " · ") }
}

struct ReadingRecord: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var title: String? = nil
    var classification: TopicClassification? = nil
    var classificationIsManual: Bool? = nil
    var automaticClassification: TopicClassification? = nil
    var purposeOverride: String? = nil
    var automaticPurpose: String? {
        let observations = notes.map { $0.title + " " + $0.text }.joined(separator: " ")
        let dataSignals = ["百分点", "占比", "峰值", "增长率", "rose from", "accounted for", "fell from"]
        if dataSignals.contains(where: { observations.localizedCaseInsensitiveContains($0) }) { return "数据描述" }
        if notes.contains(where: { ["tone", "rhetoric"].contains($0.kind) }) { return "观点展开" }
        if notes.contains(where: { $0.kind == "vocabulary" || $0.kind == "usage" }) { return "词汇积累" }
        return nil
    }
    var purpose: String? { purposeOverride == nil ? automaticPurpose : (purposeOverride?.isEmpty == true ? nil : purposeOverride) }
    var ocrText: String
    var editedText: String
    var explanation: String
    var takeaway: String? = nil
    var sourceURL: String?
    var sourceApp: String
    var pdfPath: String?
    var pdfPage: Int?
    var turns: [ChatTurn] = []
    var screenshotPath: String? = nil
    var notes: [ReadingNote] = []
    var pdfAnchor: PDFAnchor? = nil
    var ocrLines: [OCRLine] = []
}

extension ReadingRecord {
    func matchesSearch(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let fields = [title ?? "", editedText, ocrText, explanation, takeaway ?? "", purpose ?? "", classification?.topics.joined(separator: " ") ?? "", classification?.label ?? "待分类"]
            + notes.flatMap { [$0.quote, $0.title, $0.text] } + turns.map(\.text)
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct OCRLine: Codable, Identifiable {
    var id = UUID()
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var wordBoxes: [OCRWordBox] = []
}

struct OCRWordBox: Codable {
    var start: Int
    var end: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct ScreenshotRect: Codable, Identifiable {
    var id = UUID()
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct PDFAnchor: Codable {
    var page: Int
    var quote: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct ReadingNote: Codable, Identifiable {
    var id = UUID()
    var quote: String
    var kind: String
    var title: String
    var text: String
    var phonetic: String? = nil
    var matched: Bool
    var screenshotRects: [ScreenshotRect] = []
    enum CodingKeys: String, CodingKey { case id, quote, kind, title, text, phonetic, matched, screenshotRects }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        quote = try c.decode(String.self, forKey: .quote)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "usage"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "批注"
        text = try c.decode(String.self, forKey: .text)
        phonetic = try c.decodeIfPresent(String.self, forKey: .phonetic)
        matched = try c.decodeIfPresent(Bool.self, forKey: .matched) ?? false
        screenshotRects = try c.decodeIfPresent([ScreenshotRect].self, forKey: .screenshotRects) ?? []
    }
    init(quote: String, kind: String, title: String, text: String, phonetic: String? = nil, matched: Bool, screenshotRects: [ScreenshotRect] = []) {
        self.quote = quote; self.kind = kind; self.title = title; self.text = text; self.phonetic = phonetic; self.matched = matched; self.screenshotRects = screenshotRects
    }
}

struct ChatTurn: Codable, Identifiable {
    var id = UUID()
    var role: String
    var text: String
    var createdAt = Date()
}

struct VocabularyItem: Codable, Identifiable {
    var id = UUID()
    var classification: TopicClassification? = nil
    var classificationIsManual: Bool? = nil
    var word: String
    var phonetic: String? = nil
    var meaning: String
    var example: String
    var recitation: RecitationExercise? = nil
    var marked = false
    var createdAt = Date()
    var recordID: UUID? = nil
    var sourceApp: String = ""
    var sourceURL: String? = nil
    var noteID: UUID? = nil
}

extension VocabularyItem {
    func matchesSearch(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [word, meaning, example, phonetic ?? "", classification?.label ?? "待分类"]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct VocabularyDraft: Codable {
    var word: String
    var phonetic: String? = nil
    var meaning: String
    var example: String
}

struct WordAnnotationDraft: Decodable {
    var meaning: String
    var phonetic: String
    var title: String
    var annotation: String

    enum CodingKeys: String, CodingKey { case meaning, phonetic, title, annotation }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        meaning = try values.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        phonetic = try values.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "词语在此处的作用"
        annotation = try values.decodeIfPresent(String.self, forKey: .annotation) ?? ""
    }
}

struct ReadingAnalysis: Codable {
    var classification: TopicClassification? = nil
    var summary: String
    var notes: [ReadingNote]
    var vocabulary: [VocabularyDraft]
    var takeaway: String? = nil
}

struct AppPreferences: Codable {
    var endpoint = "https://api.deepseek.com"
    var model = "deepseek-flash"
    var hotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_4)
    var hotkeyModifiers: UInt32 = UInt32(cmdKey)
    var showWindowOnLaunch = true

    enum CodingKeys: String, CodingKey { case endpoint, model, hotkeyKeyCode, hotkeyModifiers, showWindowOnLaunch }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try values.decodeIfPresent(String.self, forKey: .endpoint) ?? endpoint
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? model
        hotkeyKeyCode = try values.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? hotkeyKeyCode
        hotkeyModifiers = try values.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? hotkeyModifiers
        if hotkeyKeyCode == UInt32(kVK_ANSI_R) && hotkeyModifiers == UInt32(optionKey | cmdKey) {
            hotkeyKeyCode = UInt32(kVK_ANSI_4)
            hotkeyModifiers = UInt32(cmdKey)
        }
        showWindowOnLaunch = try values.decodeIfPresent(Bool.self, forKey: .showWindowOnLaunch) ?? true
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var records: [ReadingRecord] = []
    @Published var words: [VocabularyItem] = []
    @Published var sentencePatterns = SentencePatternState()
    @Published var refreshingSentencePatterns = false
    @Published var sentencePatternProgress = ""
    @Published var sentencePatternError = ""
    var sentencePatternRefreshTask: Task<Void, Never>?
    @Published var expressionLinks = ExpressionLinkState()
    @Published var refreshingExpressionLinks = false
    @Published var expressionLinkProgress = ""
    @Published var expressionLinkError = ""
    var expressionRefreshTask: Task<Void, Never>?

    @Published var preferences: AppPreferences = .init()
    @Published var apiKey: String = ""
    @Published var selectedRecordID: UUID?
    @Published var requestedReadingID: UUID?
    @Published var statusMessage = "就绪"
    @Published var analyzingRecordIDs: Set<UUID> = []

    let undoManager = UndoManager()
    private struct UndoState {
        var recordIDs: Set<UUID>
        var wordIDs: Set<UUID>
        var records: [(Int, ReadingRecord)]
        var words: [(Int, VocabularyItem)]
        var selection: UUID?
    }
    private func checkpoint(recordIDs: Set<UUID> = [], wordIDs: Set<UUID> = [], name: String) {
        let state = UndoState(recordIDs: recordIDs, wordIDs: wordIDs,
            records: records.enumerated().filter { recordIDs.contains($0.element.id) }.map { ($0.offset, $0.element) },
            words: words.enumerated().filter { wordIDs.contains($0.element.id) }.map { ($0.offset, $0.element) }, selection: selectedRecordID)
        undoManager.registerUndo(withTarget: self) { target in target.restore(state, name: name) }
        undoManager.setActionName(name)
    }
    private func restore(_ state: UndoState, name: String) {
        var affectedWords = state.wordIDs
        if state.records.isEmpty {
            affectedWords.formUnion(words.filter { state.recordIDs.contains($0.recordID ?? UUID()) }.map(\.id))
        }
        checkpoint(recordIDs: state.recordIDs, wordIDs: affectedWords, name: name)
        records.removeAll { state.recordIDs.contains($0.id) }
        words.removeAll { affectedWords.contains($0.id) }
        for (index, record) in state.records { records.insert(record, at: min(index, records.count)) }
        for (index, word) in state.words { words.insert(word, at: min(index, words.count)) }
        selectedRecordID = records.contains { $0.id == state.selection } ? state.selection : records.first?.id
        persistRecords(); persistWords()
    }
    func restoreAutomaticClassification(for id: UUID) async {
        guard let original = records.first(where: { $0.id == id }) else { return }
        do {
            let topic: TopicClassification
            if let cached = original.automaticClassification { topic = cached }
            else { topic = try await ReadingAPI.classify(text: original.editedText, preferences: preferences, apiKey: apiKey) }
            guard var current = records.first(where: { $0.id == id }),
                  current.editedText == original.editedText, current.classification == original.classification,
                  current.classificationIsManual == original.classificationIsManual else { return }
            current.classification = topic; current.automaticClassification = topic; current.classificationIsManual = false
            update(current); statusMessage = "已恢复自动分类"
        } catch { statusMessage = "恢复自动分类失败：\(error.localizedDescription)" }
    }
    func restoreWordClassification(_ id: UUID) {
        guard var word = words.first(where: { $0.id == id }) else { return }
        word.classification = records.first { $0.id == word.recordID }?.classification
        word.classificationIsManual = false; updateWord(word)
    }

    let folder: URL
    private let keychainService = "com.alexjiang.suibiancha.api-key"

    init(storageFolder: URL? = nil, loadCredential: Bool = true) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = storageFolder ?? base.appendingPathComponent("Suibiancha", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        undoManager.levelsOfUndo = 100
        records = read([ReadingRecord].self, name: "readings.json") ?? []
        words = read([VocabularyItem].self, name: "vocabulary.json") ?? []
        expressionLinks = read(ExpressionLinkState.self, name: "expression-links.json") ?? .init()
        sentencePatterns = read(SentencePatternState.self, name: "sentence-patterns.json") ?? .init()
        preferences = read(AppPreferences.self, name: "preferences.json") ?? .init()
        apiKey = loadCredential ? loadKey() : ""
    }

    var selectedRecord: ReadingRecord? { records.first { $0.id == selectedRecordID } }

    func setClassification(_ topic: TopicClassification, for id: UUID) {
        guard var record = records.first(where: { $0.id == id }) else { return }
        record.classification = topic; record.classificationIsManual = true; update(record)
    }
    func refreshExistingAnalyses() async {
        let originals = records.filter { !$0.editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let reportURL = folder.appendingPathComponent("analysis-refresh-status.json")
        var completed = 0
        var failures: [String] = []
        func report(_ finished: Bool) {
            let report: [String: Any] = ["total": originals.count, "completed": completed, "failures": failures, "finished": finished]
            if let data = try? JSONSerialization.data(withJSONObject: report) { try? data.write(to: reportURL, options: .atomic) }
        }
        report(false)
        do {
            let backups = folder.appendingPathComponent("Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            try exportBackup(to: backups.appendingPathComponent("before-analysis-refresh-\(Int(Date().timeIntervalSince1970)).zip"))
        } catch { failures.append("备份失败：\(error.localizedDescription)"); report(true); return }
        for (index, original) in originals.enumerated() {
            statusMessage = "正在更新已有精读 \(index + 1)/\(originals.count)…"
            analyzingRecordIDs.insert(original.id)
            do {
                var analysis = try await ReadingAPI.analyze(text: original.editedText, ocrLines: original.ocrLines, preferences: preferences, apiKey: apiKey)
                guard let latest = records.first(where: { $0.id == original.id }), latest.editedText == original.editedText else {
                    analyzingRecordIDs.remove(original.id); failures.append("\(original.id)：原文已修改，跳过"); report(false); continue
                }
                let linked = Set(words.filter { $0.recordID == original.id }.compactMap(\.noteID))
                for old in latest.notes where linked.contains(old.id) {
                    if let i = analysis.notes.firstIndex(where: { $0.quote.caseInsensitiveCompare(old.quote) == .orderedSame }) {
                        analysis.notes[i].id = old.id
                    } else { analysis.notes.append(old) }
                }
                if applyAnalysis(analysis, to: original.id, expectedText: original.editedText) { completed += 1 }
            } catch { failures.append("\(original.id)：\(error.localizedDescription)") }
            analyzingRecordIDs.remove(original.id)
            report(false)
        }
        statusMessage = "已有精读更新完成：\(completed)/\(originals.count)" + (failures.isEmpty ? "" : "，\(failures.count)条未更新")
        report(true)
    }

    private var classifyingHistory = false
    func classifyExistingRecords() async {
        guard !apiKey.isEmpty, !classifyingHistory else { return }
        classifyingHistory = true
        defer { classifyingHistory = false }
        for original in records.filter({ $0.classification == nil && !$0.editedText.isEmpty }) {
            do {
                let topic = try await ReadingAPI.classify(text: original.editedText, preferences: preferences, apiKey: apiKey)
                guard var current = records.first(where: { $0.id == original.id }), current.classification == nil,
                      current.editedText == original.editedText, current.classificationIsManual != true else { continue }
                current.classification = topic; current.automaticClassification = topic; update(current, undoable: false)
            } catch { statusMessage = "历史话题分类失败：\(error.localizedDescription)；下次打开时重试"; return }
        }
        for index in words.indices where words[index].classification == nil && words[index].classificationIsManual != true {
            words[index].classification = records.first { $0.id == words[index].recordID }?.classification
        }
        persistWords()
    }

    func renameRecord(_ id: UUID, to title: String) {
        guard var record = records.first(where: { $0.id == id }) else { return }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        record.title = cleaned.isEmpty ? nil : cleaned
        update(record)
    }

    func add(_ record: ReadingRecord) {
        checkpoint(recordIDs: [record.id], name: "添加记录")
        records.insert(record, at: 0); selectedRecordID = record.id; persistRecords()
    }
    func saveScreenshot(_ image: CGImage, for recordID: UUID) throws -> String {
        let file = folder.appendingPathComponent("capture-\(recordID.uuidString).png")
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw APIError.badResponse("无法将截图编码为 PNG")
        }
        try data.write(to: file, options: .atomic)
        return file.path
    }
    func update(_ record: ReadingRecord, undoable: Bool = true) {
        guard let i = records.firstIndex(where: { $0.id == record.id }) else { return }
        if undoable { checkpoint(recordIDs: [record.id], wordIDs: Set(words.filter { $0.recordID == record.id }.map(\.id)), name: "修改记录") }
        let topicChanged = records[i].classification != record.classification
        let sourceChanged = records[i].sourceURL != record.sourceURL
        records[i] = record; persistRecords()
        if topicChanged {
            for index in words.indices where words[index].recordID == record.id && words[index].classificationIsManual != true { words[index].classification = record.classification }
            persistWords()
        }
        if sourceChanged {
            for index in words.indices where words[index].recordID == record.id { words[index].sourceURL = record.sourceURL }
            persistWords()
        }
    }
    @discardableResult
    func applyAnalysis(_ analysis: ReadingAnalysis, to recordID: UUID, expectedText: String) -> Bool {
        guard var record = records.first(where: { $0.id == recordID }), record.editedText == expectedText else { return false }
        if let topic = analysis.classification {
            record.automaticClassification = topic
            if record.classificationIsManual != true { record.classification = topic }
        }
        record.explanation = analysis.summary
        record.takeaway = analysis.takeaway
        record.notes = analysis.notes
        update(record, undoable: false)
        return true
    }
    func addWord(_ word: VocabularyItem) {
        guard !words.contains(where: { $0.recordID == word.recordID && $0.word.caseInsensitiveCompare(word.word) == .orderedSame }) else { return }
        var word = word
        if word.classification == nil { word.classification = records.first { $0.id == word.recordID }?.classification }
        checkpoint(wordIDs: [word.id], name: "添加词条")
        words.insert(word, at: 0)
        persistWords()
    }
    func updateWord(_ word: VocabularyItem, undoable: Bool = true) {
        guard let i = words.firstIndex(where: { $0.id == word.id }) else { return }
        if undoable { checkpoint(wordIDs: [word.id], name: "修改词条") }
        var updated = word
        if words[i].word != word.word || words[i].meaning != word.meaning || words[i].example != word.example {
            updated.recitation = nil
        }
        words[i] = updated; persistWords()

    }
    func deleteWord(_ id: UUID) { checkpoint(wordIDs: [id], name: "删除词条"); words.removeAll { $0.id == id }; persistWords() }
    func deleteRecord(_ id: UUID) {
        checkpoint(recordIDs: [id], wordIDs: Set(words.filter { $0.recordID == id }.map(\.id)), name: "删除记录")
        // Keep screenshot files so a deleted record can be restored with Undo.
        records.removeAll { $0.id == id }
        words.removeAll { $0.recordID == id }
        if selectedRecordID == id { selectedRecordID = records.first?.id }
        persistRecords(); persistWords()
    }
    func savePreferences() {
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        write(preferences, name: "preferences.json")
        saveKey(apiKey)
        scheduleExpressionRefresh()
        scheduleSentencePatternRefresh()
    }
    func exportWords() throws -> URL {
        let url = folder.appendingPathComponent("单词本导出.csv")
        let rows = ["单词,音标,释义,例句,已标记,来源应用,来源网址,话题"] + words.map { "\($0.word.csv),\(($0.phonetic ?? "").csv),\($0.meaning.csv),\($0.example.csv),\($0.marked ? "是" : "否"),\($0.sourceApp.csv),\(($0.sourceURL ?? "").csv),\(($0.classification?.label ?? "待分类").csv)" }
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8); return url
    }
    func exportBackup(to destination: URL) throws {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("suibiancha-backup-\(UUID().uuidString)", isDirectory: true)
        let screenshots = staging.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var backupRecords = records
        for index in backupRecords.indices {
            guard let path = backupRecords[index].screenshotPath else { continue }
            let source = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let name = source.lastPathComponent
            try FileManager.default.copyItem(at: source, to: screenshots.appendingPathComponent(name))
            backupRecords[index].screenshotPath = "Screenshots/\(name)"
        }
        try JSONEncoder().encode(backupRecords).write(to: staging.appendingPathComponent("readings.json"), options: .atomic)
        try JSONEncoder().encode(words).write(to: staging.appendingPathComponent("vocabulary.json"), options: .atomic)
        try JSONEncoder().encode(expressionLinks).write(to: staging.appendingPathComponent("expression-links.json"), options: .atomic)
        try JSONEncoder().encode(sentencePatterns).write(to: staging.appendingPathComponent("sentence-patterns.json"), options: .atomic)
        let articleLibrary = folder.appendingPathComponent("article-practice.json")
        if FileManager.default.fileExists(atPath: articleLibrary.path) {
            try FileManager.default.copyItem(at: articleLibrary, to: staging.appendingPathComponent("article-practice.json"))
        }
        try "此备份包含精读记录、词条和截图，不包含 API Key 或原始 PDF 文件。".write(to: staging.appendingPathComponent("说明.txt"), atomically: true, encoding: .utf8)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", staging.path, destination.path]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw APIError.badResponse("创建 ZIP 备份失败（\(process.terminationStatus)）") }
    }
    private func persistRecords() { write(records, name: "readings.json"); scheduleExpressionRefresh(); scheduleSentencePatternRefresh() }
    private func persistWords() { write(words, name: "vocabulary.json") }
    private func read<T: Decodable>(_ type: T.Type, name: String) -> T? { try? JSONDecoder().decode(type, from: Data(contentsOf: folder.appendingPathComponent(name))) }
    private func write<T: Encodable>(_ value: T, name: String) { if let data = try? JSONEncoder().encode(value) { try? data.write(to: folder.appendingPathComponent(name), options: .atomic) } }
    private func loadKey() -> String {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        q.removeAll()
        let stored = String(data: data, encoding: .utf8) ?? ""
        let cleaned = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned != stored { saveKey(cleaned) }
        return cleaned
    }
    private func saveKey(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService]
        SecItemDelete(query as CFDictionary)
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var item = query; item[kSecValueData as String] = Data(cleaned.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

private extension String {
    var csv: String { "\"" + replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
