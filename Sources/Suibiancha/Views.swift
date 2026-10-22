import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import ServiceManagement

private extension Date {
    var compactReadingDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: self)
    }
}

struct RootView: View {
    @ObservedObject var store: AppStore
    let capture: () -> Void
    let openPDF: (URL, Int?, String?, PDFAnchor?) -> Void
    let selectedPDFAnchor: () -> PDFAnchor?
    @State private var tab = 0
    @State private var statusPulse = false
    @State private var showGlobalSearch = false
    @State private var vocabularySearch = ""
    @StateObject private var articleLibrary = ArticlePracticeLibrary()
    @State private var auxiliaryPane: AuxiliaryPane?
    @State private var lastReadingTab = 0
    @State private var lastCollectionTab = 2

    private enum AuxiliaryPane: String, Identifiable {
        case settings, guide
        var id: String { rawValue }
        var title: String {
            switch self {
            case .settings: return "设置"
            case .guide: return "学习指南"
            }
        }
    }

    private var primaryTab: Binding<Int> {
        Binding(get: {
            switch tab {
            case 0, 1: return 0
            case 2, 6: return 1
            default: return 2
            }
        }, set: { section in
            switch section {
            case 0: tab = lastReadingTab
            case 1: tab = lastCollectionTab
            default: tab = 7
            }
        })
    }

    private func secondaryNavigation(_ title: String, destination: Int) -> some View {
        Button { tab = destination } label: {
            Text(title).font(tab == destination ? BirdyDesign.emphasis : BirdyDesign.body)
                .foregroundStyle(tab == destination ? Color.primary : .secondary)
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) {
                    if tab == destination {
                        Rectangle().fill(Color.primary.opacity(0.35)).frame(height: 1)
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(tab == destination ? "已选择" : "未选择")
    }

    private var isProcessingStatus: Bool {
        store.statusMessage.contains("正在生成") || store.statusMessage.contains("正在截取") || store.statusMessage.contains("正在识别")
    }
    private var isAttentionStatus: Bool {
        isProcessingStatus || store.statusMessage.hasPrefix("精读完成")
            || store.statusMessage.hasPrefix("自动精读失败")
            || store.statusMessage.hasPrefix("单词释义已补全")
    }
    private var isErrorStatus: Bool {
        store.statusMessage.contains("失败") || store.statusMessage.contains("错误")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Birdy").font(BirdyDesign.brand)
                HStack(spacing: 7) {
                    if isProcessingStatus {
                        ProgressView().controlSize(.small).tint(BirdyDesign.accent)
                    } else if isAttentionStatus {
                        Circle().fill(BirdyDesign.accent).frame(width: 6, height: 6)
                    }
                    Text(store.statusMessage).font(isAttentionStatus ? BirdyDesign.emphasis : BirdyDesign.caption).lineLimit(1)
                }
                .foregroundStyle(isErrorStatus ? Color.red : (isAttentionStatus ? BirdyDesign.accent : Color.secondary))
                .opacity(isAttentionStatus && statusPulse ? 0.48 : 1)
                Spacer()
                HStack(spacing: 8) {
                    Button { showGlobalSearch = true } label: {
                        Image(systemName: "magnifyingglass").frame(width: 20, height: 20)
                    }.keyboardShortcut("f", modifiers: .command)
                        .accessibilityLabel("全局搜索").help("搜索全部精读记录和单词本 · ⌘F")
                    Button { capture() } label: {
                        Image(systemName: "viewfinder").frame(width: 20, height: 20)
                    }.keyboardShortcut("r", modifiers: [.command, .option])
                        .accessibilityLabel("框选精读").help("截图框选精读 · ⌥⌘R")
                    Button { auxiliaryPane = .settings } label: {
                        Image(systemName: "gearshape").frame(width: 20, height: 20)
                    }.accessibilityLabel("设置").help("设置 · ⌘,")
                        .keyboardShortcut(",", modifiers: .command)
                    Button { auxiliaryPane = .guide } label: {
                        Image(nsImage: BlueWrenIcon.menuBarImage()).resizable().scaledToFit()
                            .frame(width: 20, height: 20)
                    }.accessibilityLabel("学习指南").help("Birdy 学习指南")
                }
            }.padding()
            Picker("主导航", selection: primaryTab) {
                Text("阅读").tag(0)
                Text("积累").tag(1)
                Text("表达").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal)
            if tab == 0 || tab == 1 {
                HStack(spacing: 24) {
                    secondaryNavigation("原文", destination: 0)
                    secondaryNavigation("精读记录", destination: 1)
                }.padding(.top, 12).padding(.bottom, 8)
            } else if tab == 2 || tab == 6 {
                HStack(spacing: 24) {
                    secondaryNavigation("单词本", destination: 2)
                    secondaryNavigation("句式库", destination: 6)
                }.padding(.top, 12).padding(.bottom, 8)
            }
            Group {
                if tab == 0 { OriginalsWall(store: store, openRecord: { record in store.selectedRecordID = record.id; tab = 1 }) }
                else if tab == 1 { ReadingPane(store: store, openPDF: openPDF, selectedPDFAnchor: selectedPDFAnchor) }
                else if tab == 2 { VocabularyPane(store: store, initialSearch: vocabularySearch, openRecord: { id in store.selectedRecordID = id; tab = 1 }) }
                else if tab == 6 { SentencePatternPane(store: store, openRecord: { id in store.selectedRecordID = id; tab = 1 }) }
                else { ArticlePracticePane(store: store, library: articleLibrary) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.font(BirdyDesign.control).tint(BirdyDesign.accent).frame(minWidth: 820, minHeight: 600)
            .onChange(of: tab) { _, value in
                if value == 0 || value == 1 { lastReadingTab = value }
                if value == 2 || value == 6 { lastCollectionTab = value }
            }
            .sheet(item: $auxiliaryPane) { pane in
                VStack(spacing: 0) {
                    HStack {
                        Text(pane.title).font(BirdyDesign.section)
                        Spacer()
                        Button("完成") { auxiliaryPane = nil }.keyboardShortcut(.cancelAction)
                    }.padding(16)
                    Divider()
                    Group {
                        switch pane {
                        case .settings: SettingsPane(store: store)
                        case .guide: LearningGuidePane()

                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.font(BirdyDesign.control)
                    .frame(width: 740, height: 680)
            }
            .onReceive(store.$requestedReadingID) { id in
                if let id { store.selectedRecordID = id; tab = 1 }
            }
            .sheet(isPresented: $showGlobalSearch) {
                GlobalSearchPane(store: store, openRecord: { id in
                    store.selectedRecordID = id; tab = 1; showGlobalSearch = false
                }, openWord: { item in
                    vocabularySearch = item.word; tab = 2; showGlobalSearch = false
                })
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) { statusPulse = true }
                if store.selectedRecordID == nil || !store.records.contains(where: { $0.id == store.selectedRecordID }) {
                    store.selectedRecordID = store.records.first?.id
                }
            }
    }
}

private struct GlobalSearchPane: View {
    @ObservedObject var store: AppStore
    let openRecord: (UUID) -> Void
    let openWord: (VocabularyItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var records: [ReadingRecord] { hasQuery ? store.records.filter { $0.matchesSearch(query) } : [] }
    private var words: [VocabularyItem] { hasQuery ? store.words.filter { $0.matchesSearch(query) } : [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("全局搜索").font(BirdyDesign.section)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("搜索主题、词条、句子、释义或精读内容", text: $query)
                .textFieldStyle(.roundedBorder).focused($focused)
            if !hasQuery {
                Text("搜索全部精读记录和单词本，不受当前主题筛选限制。")
                    .font(BirdyDesign.caption).foregroundStyle(BirdyDesign.secondaryText)
                Spacer()
            } else if records.isEmpty && words.isEmpty {
                ContentUnavailableView("没有找到内容", systemImage: "magnifyingglass", description: Text("试试其他主题、词语或句子片段。"))
            } else {
                List {
                    if !records.isEmpty {
                        Section("精读记录 · \(records.count)") {
                            ForEach(records) { record in
                                Button { openRecord(record.id) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(record.title ?? String(record.editedText.prefix(100))).font(BirdyDesign.body).lineLimit(2)
                                        Text(record.classification?.label ?? "待分类").font(BirdyDesign.metadata).foregroundStyle(BirdyDesign.secondaryText)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if !words.isEmpty {
                        Section("单词本 · \(words.count)") {
                            ForEach(words) { word in
                                Button { openWord(word) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(word.word).font(BirdyDesign.quote)
                                        Text(word.meaning).font(BirdyDesign.body).lineLimit(2)
                                        Text(word.classification?.label ?? "待分类").font(BirdyDesign.metadata).foregroundStyle(BirdyDesign.secondaryText)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.listStyle(.inset)
            }
        }.padding(20).frame(width: 680, height: 520).font(BirdyDesign.control)
            .onAppear { focused = true }
    }
}

/// An Eagle-like, scan-first page: screenshot records show the original crop only;
/// text-selection records keep a text card because they have no screenshot.
struct OriginalsWall: View {
    @ObservedObject var store: AppStore
    let openRecord: (ReadingRecord) -> Void
    @State private var search = ""
    @State private var topic = "全部"

    private var visibleRecords: [ReadingRecord] {
        store.records.filter {
            (topic == "全部" || ($0.classification?.category ?? "待分类") == topic)
                && (search.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(search)
                || $0.editedText.localizedCaseInsensitiveContains(search)
                || $0.explanation.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = geometry.size.width < 1000 ? 20 : 28
            HStack(spacing: 0) {
                BirdyCategorySidebar(categories: TopicClassification.categories + ["待分类"], selection: $topic) { name in
                    store.records.filter { name == "全部" || ($0.classification?.category ?? "待分类") == name }.count
                }.frame(width: geometry.size.width < 1000 ? 164 : 190)
                Divider()
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        BirdyLibraryTitle(title: topic == "全部" ? "原文摘录" : topic, count: "\(visibleRecords.count) 段")
                        Spacer(minLength: 0)
                        BirdyLibrarySearch(placeholder: "搜索原句", text: $search).frame(maxWidth: 300)
                    }.padding(.horizontal, inset).padding(.vertical, 14)
                    Divider()
                    if visibleRecords.isEmpty {
                        ContentUnavailableView(store.records.isEmpty ? "还没有摘录" : "没有找到原句",
                            systemImage: "text.viewfinder",
                            description: Text(store.records.isEmpty ? "选中文字后按 ⌘4 直接精读；没有选中文字时进入截图框选。也可以右键使用「服务 → Birdy 精读」。" : "试试其他搜索词，或切换到全部话题。"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20, alignment: .top)], alignment: .leading, spacing: 20) {
                                ForEach(visibleRecords) { record in
                                    Button { openRecord(record) } label: { OriginalsCard(record: record) }
                                        .buttonStyle(.plain).help("打开这段原文的精读记录")
                                }
                            }.padding(inset)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct OriginalsCard: View {
    let record: ReadingRecord

    private var screenshot: NSImage? {
        guard let path = record.screenshotPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var readableText: String {
        let text = record.editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            if record.editedText == record.ocrText, !record.ocrLines.isEmpty {
                return CaptureService.readableText(from: record.ocrLines)
            }
            return text
        }
        if !record.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return record.ocrText }
        return record.notes.map(\.quote).joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = screenshot {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 9) {
                if screenshot == nil {
                    Text(TextFlow.prose(readableText.isEmpty ? (record.title ?? "无识别文本") : readableText))
                        .font(BirdyDesign.quote)
                        .lineSpacing(3).lineLimit(9).multilineTextAlignment(.leading)
                        .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 5) {
                    Text(record.classification?.topics.first ?? record.classification?.category ?? "待分类").lineLimit(1)
                    Text("·")
                    Text(record.createdAt.compactReadingDate).fixedSize()
                    Spacer(minLength: 0)
                    if !record.notes.isEmpty {
                        Text("\(record.notes.count) 条观察").foregroundStyle(BirdyDesign.accent)
                    } else if !record.explanation.isEmpty {
                        Text("已精读").foregroundStyle(BirdyDesign.accent)
                    }
                }.font(BirdyDesign.metadata).foregroundStyle(.secondary)
            }.padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct InlineReadingOverlay: View {
    @ObservedObject var store: AppStore
    let recordID: UUID
    var errorMessage: String? = nil
    var retry: (() -> Void)? = nil
    let close: () -> Void
    @State private var question = ""
    @State private var busy = false
    @State private var error = ""

    private var record: ReadingRecord? { store.records.first { $0.id == recordID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(nsImage: BlueWrenIcon.menuBarImage())
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(BirdyDesign.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Birdy 精读").font(BirdyDesign.heading)
                    Text(record?.sourceApp ?? "正在读取片段").font(BirdyDesign.metadata).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }.padding(.horizontal, 14).padding(.vertical, 12)
            Rectangle().fill(.white.opacity(0.7)).frame(height: 1)
            if let record {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !record.explanation.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("阅读主线", systemImage: "sparkle.magnifyingglass")
                                    .font(BirdyDesign.label).foregroundStyle(BirdyDesign.accent)
                                Text(record.explanation).font(BirdyDesign.emphasis).lineSpacing(2).textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(BirdyDesign.tint, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.72), lineWidth: 1))
                        }
                        if !record.notes.isEmpty {
                            HStack(alignment: .firstTextBaseline) {
                                Text("语言观察").font(BirdyDesign.label).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(record.notes.count)").font(BirdyDesign.metadata).foregroundStyle(BirdyDesign.secondaryText)
                            }.padding(.top, 1).padding(.bottom, -5)
                            ForEach(record.notes) { note in
                                let alreadySaved = store.words.contains {
                                    $0.recordID == record.id && $0.word.caseInsensitiveCompare(note.quote) == .orderedSame
                                }
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(alignment: .center, spacing: 6) {
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(noteKindLabel(note.kind))
                                                .font(BirdyDesign.label)
                                                .foregroundStyle(BirdyDesign.accent)
                                            Text(note.title).font(BirdyDesign.heading)
                                        }
                                        Spacer(minLength: 2)
                                        Button {
                                            guard !alreadySaved else { return }
                                            let item = VocabularyItem(word: note.quote,
                                                                      phonetic: note.phonetic,
                                                                      meaning: "\(note.title)：\(note.text)",
                                                                      example: note.quote,
                                                                      recordID: record.id,
                                                                      sourceApp: record.sourceApp,
                                                                      sourceURL: record.sourceURL)
                                            store.addWord(item)
                                            store.statusMessage = "已加入单词本：\(note.quote)"
                                        } label: {
                                            Image(systemName: "book.closed")
                                                .font(BirdyDesign.body)
                                                .foregroundStyle(alreadySaved ? BirdyDesign.accent : BirdyDesign.secondaryText)
                                                .frame(width: 28, height: 26)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(alreadySaved)
                                        .accessibilityLabel(alreadySaved ? "已加入单词本" : "加入单词本")
                                        .help(alreadySaved ? "已加入单词本" : "加入单词本")
                                    }
                                    Text(note.quote.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")).font(BirdyDesign.quote)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineSpacing(1)
                                        .textSelection(.enabled)
                                    if note.kind == "vocabulary", let phonetic = note.phonetic, !phonetic.isEmpty {
                                        Text(phonetic)
                                            .font(BirdyDesign.phonetic)
                                            .italic()
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
                                    Text(note.text).font(BirdyDesign.body).lineSpacing(2).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                                .background(BirdyDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                                    LinearGradient(colors: [.white.opacity(0.95), .blue.opacity(0.12), .white.opacity(0.58)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1
                                ))
                            }
                        }
                        if let takeaway = record.takeaway, !takeaway.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Capsule().fill(Color.blue.opacity(0.5)).frame(width: 2, height: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("回看").font(BirdyDesign.label).foregroundStyle(.secondary)
                                    Text(takeaway).font(BirdyDesign.emphasis).lineSpacing(1.5).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 1)
                        }
                        if record.explanation.isEmpty && record.notes.isEmpty && errorMessage == nil {
                            if store.analyzingRecordIDs.contains(record.id) {
                                ProgressView("正在生成精读…").frame(maxWidth: .infinity).padding(.vertical, 24)
                            } else {
                                Text(store.statusMessage).font(BirdyDesign.body).foregroundStyle(.secondary)
                                Text("点击便签，在 Birdy 中查看或重试").font(BirdyDesign.metadata).foregroundStyle(BirdyDesign.accent)
                            }
                        }
                        ForEach(record.turns) { turn in
                            Text((turn.role == "user" ? "我：" : "答：") + turn.text)
                                .frame(maxWidth: .infinity, alignment: .leading).font(BirdyDesign.body).padding(8)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if !error.isEmpty { Text(error).font(BirdyDesign.metadata).foregroundStyle(.red) }
                        if let errorMessage {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("这次精读没有生成：\(errorMessage)").font(BirdyDesign.metadata).foregroundStyle(.red)
                                Text("截图和识别文本已保存在 Birdy。修正设置后可以重试。")
                                    .font(BirdyDesign.metadata).foregroundStyle(.secondary)
                                if let retry { Button("重试精读", action: retry).buttonStyle(.bordered) }
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                Rectangle().fill(.white.opacity(0.72)).frame(height: 1)
                Label("点击便签回到 Birdy · 点击别处收起", systemImage: "arrow.up.forward.app")
                    .font(BirdyDesign.metadata).foregroundStyle(BirdyDesign.accent).padding(12)

            } else {
                ProgressView("正在生成精读…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.2), Color.blue.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.16))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(
            LinearGradient(colors: [.white.opacity(0.95), .blue.opacity(0.16), .white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1
        ))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }

    private func noteKindLabel(_ kind: String) -> String {
        switch kind {
        case "grammar": return "句法"
        case "vocabulary": return "词语"
        case "usage": return "用法"
        case "tone": return "语气"
        case "rhetoric": return "修辞"
        default: return "观察"
        }
    }

    private func ask(_ record: ReadingRecord) async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        busy = true; error = ""; defer { busy = false }
        do {
            var updated = store.records.first { $0.id == record.id } ?? record
            let prompt = "当前截图 OCR 原文：\n\(updated.editedText)\n\n此前精读解释：\n\(updated.explanation)\n\n用户问题：\n\(text)"
            let reply = try await ReadingAPI.complete(prompt: prompt, history: updated.turns, preferences: store.preferences, apiKey: store.apiKey)
            updated.turns += [ChatTurn(role: "user", text: text), ChatTurn(role: "assistant", text: reply)]
            store.update(updated); question = ""
        } catch { self.error = "追问失败：\(error.localizedDescription)" }
    }
}

struct ScreenshotPreview: View {
    let image: NSImage
    let notes: [ReadingNote]
    let ocrLines: [OCRLine]
    let savedWords: Set<String>
    let onAddWord: (String, String, ScreenshotRect) -> Void
    let onRemoveWord: (String) -> Void
    @Binding var selectedNoteID: UUID?
    @Binding var pinnedNoteID: UUID?
    @State private var hoveredWord: HoveredWord?

    private struct HoveredWord {
        let key: String
        let word: String
        let example: String
        let box: OCRWordBox
        let noteID: UUID?
    }

    var body: some View {
        GeometryReader { container in
            let scale = min(container.size.width / max(image.size.width, 1), container.size.height / max(image.size.height, 1))
            let displayed = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (container.size.width - displayed.width) / 2,
                                 y: (container.size.height - displayed.height) / 2)
            ZStack {
                Image(nsImage: image).resizable().frame(width: displayed.width, height: displayed.height)
                    .overlay {
                        GeometryReader { proxy in
                            ForEach(notes.filter(\.matched)) { note in
                                ForEach(note.screenshotRects) { rect in
                                    NoteHighlight(rect: rect, canvasSize: proxy.size, isSelected: selectedNoteID == note.id)
                                }
                            }
                        }
                    }
                    .position(x: container.size.width / 2, y: container.size.height / 2)
                if let hoveredWord {
                    Button {
                        addHoveredWord(hoveredWord)
                    } label: {
                        Circle()
                            .fill(savedWords.contains(hoveredWord.word.lowercased()) ? Color.green : Color.white)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(savedWords.contains(hoveredWord.word.lowercased()) ? Color.green : Color.blue, lineWidth: 1.25))
                            .overlay {
                                if savedWords.contains(hoveredWord.word.lowercased()) {
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    }
                    .padding(3)
                    .buttonStyle(.plain)
                    .disabled(savedWords.contains(hoveredWord.word.lowercased()))
                    .help(savedWords.contains(hoveredWord.word.lowercased()) ? "已在单词本" : "加入单词本：\(hoveredWord.word)")
                    .position(x: origin.x + min(displayed.width - 4.5, max(4.5, (hoveredWord.box.x + hoveredWord.box.width) * displayed.width - 4)),
                              y: origin.y + min(displayed.height - 4.5, max(4.5, (1 - hoveredWord.box.y - hoveredWord.box.height) * displayed.height + 4)))
                }
            }
            .frame(width: container.size.width, height: container.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                if let id = hoveredWord?.noteID { pinnedNoteID = id; selectedNoteID = id }
            }
            .onTapGesture(count: 2) {
                guard let hoveredWord else { return }
                if savedWords.contains(hoveredWord.word.lowercased()) {
                    onRemoveWord(hoveredWord.word)
                } else {
                    addHoveredWord(hoveredWord)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    let imagePoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
                    guard imagePoint.x >= 0, imagePoint.y >= 0,
                          imagePoint.x <= displayed.width, imagePoint.y <= displayed.height else {
                        if hoveredWord != nil { hoveredWord = nil }
                        if selectedNoteID != pinnedNoteID { selectedNoteID = pinnedNoteID }
                        return
                    }
                    let normalized = CGPoint(x: imagePoint.x / displayed.width, y: 1 - imagePoint.y / displayed.height)
                    let match = wordAt(normalized, pixelSize: displayed)
                    if hoveredWord?.key != match?.key { hoveredWord = match }
                    let nextNoteID = match?.noteID ?? pinnedNoteID
                    if selectedNoteID != nextNoteID { selectedNoteID = nextNoteID }
                case .ended:
                    if hoveredWord != nil { hoveredWord = nil }
                    if selectedNoteID != pinnedNoteID { selectedNoteID = pinnedNoteID }
                }
            }
        }
        .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private func wordAt(_ point: CGPoint, pixelSize: CGSize) -> HoveredWord? {
        var candidates: [(HoveredWord, CGRect)] = []
        for (lineIndex, line) in ocrLines.enumerated() {
            for (wordIndex, box) in line.wordBoxes.enumerated() {
                let word = Self.word(in: line.text, box: box)
                guard !word.isEmpty else { continue }
                let centerX = box.x + box.width / 2
                let centerY = box.y + box.height / 2
                let relatedNote = notes.reversed().first { note in
                    note.matched && note.screenshotRects.contains { centerX >= $0.x && centerX <= $0.x + $0.width && centerY >= $0.y && centerY <= $0.y + $0.height }
                }
                let item = HoveredWord(key: "\(lineIndex)-\(wordIndex)", word: word, example: line.text, box: box, noteID: relatedNote?.id)
                let rect = CGRect(x: box.x * pixelSize.width, y: (1 - box.y - box.height) * pixelSize.height,
                                  width: box.width * pixelSize.width, height: box.height * pixelSize.height)
                candidates.append((item, rect))
            }
        }
        if let exact = candidates.first(where: { $0.1.contains(CGPoint(x: point.x * pixelSize.width, y: (1 - point.y) * pixelSize.height)) }) { return exact.0 }
        let cursor = CGPoint(x: point.x * pixelSize.width, y: (1 - point.y) * pixelSize.height)
        return candidates.filter { $0.1.insetBy(dx: -8, dy: -8).contains(cursor) }
            .min(by: { hypot($0.1.midX - cursor.x, $0.1.midY - cursor.y) < hypot($1.1.midX - cursor.x, $1.1.midY - cursor.y) })?.0
    }

    private func addHoveredWord(_ word: HoveredWord) {
        guard !savedWords.contains(word.word.lowercased()) else { return }
        let box = word.box
        onAddWord(word.word, word.example,
                  ScreenshotRect(x: box.x, y: box.y, width: box.width, height: box.height))
    }

    private static func word(in line: String, box: OCRWordBox) -> String {
        guard box.start >= 0, box.end > box.start, box.end <= line.count else { return "" }
        let token = String(line.dropFirst(box.start).prefix(box.end - box.start))
        return token.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

private struct NoteHighlight: View {
    let rect: ScreenshotRect
    let canvasSize: CGSize
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
                .fill(Color.blue.opacity(isSelected ? 0.30 : 0.14))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.blue.opacity(isSelected ? 0.95 : 0.60), lineWidth: isSelected ? 2 : 1.25))
        .frame(width: max(4, rect.width * canvasSize.width), height: max(4, rect.height * canvasSize.height))
        .position(x: (rect.x + rect.width / 2) * canvasSize.width,
                  y: (1 - rect.y - rect.height / 2) * canvasSize.height)
        .allowsHitTesting(false)
    }
}

private struct SelectableVocabularyText: NSViewRepresentable {
    let text: String
    let savedWords: Set<String>
    var isExplanation = false
    var allowSavedSelection = false
    let onSaveSelection: (String) -> Void

    func makeNSView(context: Context) -> VocabularySelectionTextView {
        let view = VocabularySelectionTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.backgroundColor = .clear
        view.textColor = isExplanation ? .labelColor : .white
        view.font = isExplanation ? NSFont.systemFont(ofSize: 13) : BirdyDesign.sourceFont
        view.savedHighlightColor = isExplanation ? NSColor.controlAccentColor.withAlphaComponent(0.10) : NSColor.white.withAlphaComponent(0.14)
        view.defaultParagraphStyle = BirdyDesign.sourceParagraph
        view.textContainerInset = NSSize(width: 0, height: 24)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.savedWords = savedWords
        view.allowSavedSelection = allowSavedSelection
        view.onSaveSelection = onSaveSelection
        view.string = text
        return view
    }

    func updateNSView(_ view: VocabularySelectionTextView, context: Context) {
        if view.string != text { view.string = text }
        view.textStorage?.addAttribute(.paragraphStyle, value: BirdyDesign.sourceParagraph,
                                      range: NSRange(location: 0, length: (text as NSString).length))
        view.savedWords = savedWords
        view.allowSavedSelection = allowSavedSelection
        view.onSaveSelection = onSaveSelection
        view.refreshSavedHighlights()
        view.refreshSelectionControl()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: VocabularySelectionTextView, context: Context) -> CGSize? {
        let width = max(100, proposal.width ?? 600)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: nsView.font ?? BirdyDesign.sourceFont,
            .paragraphStyle: BirdyDesign.sourceParagraph
        ]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return NSSize(width: width, height: max(26, ceil(rect.height) + 52))
    }
}

private final class VocabularySelectionTextView: NSTextView {
    var onSaveSelection: ((String) -> Void)?
    var savedWords: Set<String> = []
    var allowSavedSelection = false
    var savedHighlightColor = NSColor.white.withAlphaComponent(0.14)
    private var selectedText = ""
    private var feedbackUntil = Date.distantPast
    private lazy var saveButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.cgColor
        button.layer?.cornerRadius = 7
        button.title = ""
        button.target = self
        button.action = #selector(saveSelection)
        button.isHidden = true
        addSubview(button)
        return button
    }()
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        refreshSelectionControl()
    }
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        if !flag { refreshSelectionControl() }
    }
    override func layout() {
        super.layout()
        refreshSelectionControl()
    }
    func refreshSelectionControl() {
        let selection = selectedRange()
        let source = string as NSString
        guard selection.location != NSNotFound, selection.length > 0,
              NSMaxRange(selection) <= source.length, let manager = layoutManager, let container = textContainer else {
            saveButton.isHidden = true; selectedText = ""; return
        }
        selectedText = source.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { saveButton.isHidden = true; return }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        var firstRect: NSRect?
        manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container) { rect, stop in
            firstRect = rect; stop.pointee = true
        }
        guard let rect = firstRect else { saveButton.isHidden = true; return }
        let saved = savedWords.contains(selectedText.lowercased())
        let symbol = NSImage(systemSymbolName: saved ? "checkmark.circle.fill" : "book.closed", accessibilityDescription: saved ? "已保存" : "加入单词本")
        saveButton.image = symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        saveButton.contentTintColor = NSColor(white: 0.22, alpha: 1)
        saveButton.frame.origin = NSPoint(x: max(0, min(bounds.width - 32, rect.maxX + textContainerOrigin.x - 16)),
                                         y: max(0, rect.minY + textContainerOrigin.y - 34))
        saveButton.isEnabled = !saved || allowSavedSelection
        saveButton.toolTip = allowSavedSelection ? "保存到单词本并补充下方解读：\(selectedText)" : saved ? "已加入单词本" : "加入单词本：\(selectedText)"
        saveButton.setAccessibilityLabel(saveButton.toolTip)
        saveButton.isHidden = saved && !allowSavedSelection && Date() >= feedbackUntil
    }
    func refreshSavedHighlights() {
        guard let storage = textStorage else { return }
        let source = string as NSString
        let entire = NSRange(location: 0, length: source.length)
        storage.removeAttribute(.underlineStyle, range: entire)
        storage.removeAttribute(.backgroundColor, range: entire)
        for word in savedWords where !word.isEmpty {
            var search = entire
            while search.length > 0 {
                let match = source.range(of: word, options: .caseInsensitive, range: search)
                guard match.location != NSNotFound else { break }
                storage.addAttribute(.backgroundColor, value: savedHighlightColor, range: match)
                search = NSRange(location: NSMaxRange(match), length: source.length - NSMaxRange(match))
            }
        }
    }
    @objc private func saveSelection() {
        guard !selectedText.isEmpty, allowSavedSelection || !savedWords.contains(selectedText.lowercased()) else { return }
        let value = selectedText
        onSaveSelection?(value)
        savedWords.insert(value.lowercased())
        feedbackUntil = Date().addingTimeInterval(0.9)
        refreshSavedHighlights()
        refreshSelectionControl()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in self?.refreshSelectionControl() }
    }
}

private struct TopicEditor: View {
    let classification: TopicClassification?
    var restoreAutomatic: (() -> Void)? = nil
    let save: (TopicClassification) -> Void
    @State private var showing = false
    @State private var category = "待分类"
    @State private var topics = ""
    var body: some View {
        Button {
            category = classification?.category ?? "待分类"
            topics = classification?.topics.first ?? ""
            showing = true
        } label: {
            Label(classification?.label ?? "待分类 · 点击编辑", systemImage: "tag")
                .font(BirdyDesign.metadata).foregroundStyle(BirdyDesign.accent)
        }.buttonStyle(.plain)
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("编辑话题").font(BirdyDesign.heading)
                if let restoreAutomatic {
                    Button("恢复自动分类") { restoreAutomatic(); showing = false }
                }
                Picker("主主题", selection: $category) {
                    Text("待分类").tag("待分类")
                    ForEach(TopicClassification.categories, id: \.self) { Text($0).tag($0) }
                }
                TextField("具体话题（一个）", text: $topics)
                Button("保存") {
                    save(ReadingAPI.normalizeClassification(TopicClassification(category: category,
                        topics: topics.components(separatedBy: CharacterSet(charactersIn: "、,，")))))
                    showing = false
                }.buttonStyle(.borderedProminent)
            }.padding(16).frame(width: 340)
        }
    }
}

struct ReadingPane: View {
    @ObservedObject var store: AppStore
    let openPDF: (URL, Int?, String?, PDFAnchor?) -> Void
    let selectedPDFAnchor: () -> PDFAnchor?
    @State private var question = ""
    @State private var busy = false
    @State private var pdfPage = "1"
    @State private var error = ""
    @State private var renameRecordID: UUID?
    @State private var renameDraft = ""
    @State private var showRename = false
    @State private var deleteRecordID: UUID?
    @State private var showDeleteConfirmation = false
    @State private var showAllTurns = false
    @State private var selectedNoteID: UUID?
    @State private var pinnedNoteID: UUID?
    @State private var enrichingVocabularyIDs: Set<UUID> = []
    @State private var pendingAnnotations: [UUID: (recordID: UUID, word: String)] = [:]
    @State private var topicFilter = "全部"
    @State private var recordSearch = ""
    private var visibleRecords: [ReadingRecord] {
        store.records.filter {
            (topicFilter == "全部" || ($0.classification?.category ?? "待分类") == topicFilter)
                && (recordSearch.isEmpty || [$0.title ?? "", $0.editedText, $0.explanation].contains { $0.localizedCaseInsensitiveContains(recordSearch) })
        }
    }
    var body: some View {
        GeometryReader { geometry in
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("精读记录").font(BirdyDesign.heading)
                        Spacer()
                        Text("\(visibleRecords.count) 段").font(BirdyDesign.metadata).foregroundStyle(.secondary)
                    }
                    BirdyLibrarySearch(placeholder: "搜索记录", text: $recordSearch)
                Picker("主题", selection: $topicFilter) {
                    Text("全部话题").tag("全部")
                    Text("待分类").tag("待分类")
                    ForEach(TopicClassification.categories, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().accessibilityLabel("筛选精读话题")
                }.padding(16)
                Divider()
            List(selection: $store.selectedRecordID) {
                ForEach(visibleRecords) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Text(record.title ?? (record.editedText.isEmpty ? "新截图" : String(record.editedText.prefix(42))))
                                .font(BirdyDesign.emphasis).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                            Menu {
                                Button("重命名…") { renameRecordID = record.id; renameDraft = record.title ?? String(record.editedText.prefix(42)); showRename = true }
                                Button("删除截图记录", role: .destructive) { deleteRecordID = record.id; showDeleteConfirmation = true }
                            } label: {
                                Image(systemName: "ellipsis.circle").foregroundStyle(BirdyDesign.secondaryText)
                                    .frame(width: 24, height: 24)
                            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                .accessibilityLabel("更多").help("重命名或删除记录")
                        }
                        HStack(spacing: 8) {
                            Text(record.classification?.label ?? "待分类").lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let purpose = record.purpose { Text(purpose).fixedSize() }
                        }.font(BirdyDesign.metadata).foregroundStyle(BirdyDesign.secondaryText)
                        Text(record.createdAt.compactReadingDate).font(BirdyDesign.metadata).foregroundStyle(.secondary)
                    }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).tag(record.id as UUID?)
                }.onDelete { offsets in for i in offsets { store.deleteRecord(visibleRecords[i].id) } }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
                if visibleRecords.isEmpty {
                    Text("没有符合条件的记录").font(BirdyDesign.caption).foregroundStyle(.secondary).padding(16)
                }
            }.frame(width: geometry.size.width < 1000 ? 230 : 260).background(BirdyDesign.quietSurface)
            Divider()
            if let record = store.selectedRecord { detail(record) }
            else {
                ContentUnavailableView(store.records.isEmpty ? "还没有记录" : "没有符合条件的记录", systemImage: "text.viewfinder",
                    description: Text(store.records.isEmpty ? "选中文字后按 ⌘4 开始精读。" : "试试其他搜索词，或切换到全部话题。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        }
        .onChange(of: topicFilter) { _, _ in selectVisibleRecord() }
        .onChange(of: recordSearch) { _, _ in selectVisibleRecord() }
        .task { await store.classifyExistingRecords() }
        .onChange(of: store.selectedRecordID) { _, id in pdfPage = String(store.records.first(where: { $0.id == id })?.pdfPage ?? 1) }
        .alert("重命名截图记录", isPresented: $showRename) {
            TextField("记录名称", text: $renameDraft)
            Button("保存") { if let id = renameRecordID { store.renameRecord(id, to: renameDraft) } }
            Button("取消", role: .cancel) {}
        } message: { Text("名称会显示在历史记录列表中。") }
        .confirmationDialog("删除这条截图记录？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除记录和截图", role: .destructive) { if let id = deleteRecordID { store.deleteRecord(id) } }
            Button("取消", role: .cancel) {}
        } message: { Text("关联的截图、精读和单词本词条也会一起删除。") }
    }
    @ViewBuilder private func detail(_ record: ReadingRecord) -> some View {
        GeometryReader { dimensions in
            let inset: CGFloat = dimensions.size.width < 800 ? 20 : 28
            let cardColumns = dimensions.size.width >= 1050
                ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                : [GridItem(.flexible())]
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(record.title ?? record.classification?.topics.first ?? "精读记录")
                        .font(BirdyDesign.section).lineLimit(2)
                    Text("\(record.createdAt.compactReadingDate) · \(record.sourceApp)")
                        .font(BirdyDesign.metadata).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, inset).padding(.top, 18).padding(.bottom, 12)
                ViewThatFits(in: .horizontal) {
                    recordControls(record)
                    recordControls(record, stacked: true)
                }.padding(.horizontal, inset).padding(.bottom, 14)
                Divider()
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 20) {

                        if !record.editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let excerpt = record.editedText == record.ocrText && !record.ocrLines.isEmpty
                                ? CaptureService.readableText(from: record.ocrLines)
                                : record.editedText
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("原文").font(BirdyDesign.label).foregroundStyle(.white.opacity(0.75))
                                }
                                SelectableVocabularyText(text: excerpt,
                                    savedWords: Set(store.words.filter { $0.recordID == record.id }.map { $0.word.lowercased() }), allowSavedSelection: true) { selection in
                                    saveVocabulary(word: selection, meaning: "", example: excerpt, for: record, addAnnotation: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .background(BirdyDesign.sourceBackground, in: RoundedRectangle(cornerRadius: 10))
                        }
                                VStack(alignment: .leading, spacing: 20) {
                                    if !record.explanation.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("本段线索").font(BirdyDesign.label).foregroundStyle(BirdyDesign.accent)
                                            Text(record.explanation).font(BirdyDesign.emphasis).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                    } else if busy || store.analyzingRecordIDs.contains(record.id) {
                                        HStack(spacing: 9) {
                                            ProgressView().controlSize(.small).tint(BirdyDesign.accent)
                                            Text("正在生成精读与批注…")
                                                .font(BirdyDesign.emphasis)
                                                .foregroundStyle(BirdyDesign.accent)
                                        }.padding(.vertical, 8)
                                    } else {
                                        Text("这段原文还没有精读内容。")
                                            .font(BirdyDesign.body).foregroundStyle(.secondary).padding(.vertical, 8)
                                    }
                                    ForEach(pendingAnnotations.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                                        if let pending = pendingAnnotations[id], pending.recordID == record.id {
                                            HStack(spacing: 9) {
                                                ProgressView().controlSize(.small)
                                                Text("正在补充「\(pending.word)」的语境解读、普通说法和使用提示…")
                                                    .font(BirdyDesign.body)
                                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                                .background(BirdyDesign.tint, in: RoundedRectangle(cornerRadius: 9))
                                        }
                                    }
                                    if !record.notes.isEmpty {
                                        HStack {
                                            Text("原文观察").font(BirdyDesign.heading).foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(record.notes.count) 处").font(BirdyDesign.caption).foregroundStyle(BirdyDesign.secondaryText)
                                        }
                                        LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 20) {
                                            ForEach(record.notes) { note in
                                                let alreadySaved = store.words.contains {
                                                    $0.recordID == record.id && $0.word.caseInsensitiveCompare(note.quote) == .orderedSame
                                                }
                                                VStack(alignment: .leading, spacing: 5) {
                                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                        Text(note.kind == "grammar" ? "句法" : note.kind == "vocabulary" ? "词语" : note.kind == "tone" ? "语气" : note.kind == "rhetoric" ? "结构" : "用法")
                                                            .font(BirdyDesign.label).foregroundStyle(BirdyDesign.accent)
                                                        Text(note.title).font(BirdyDesign.heading)
                                                        Spacer(minLength: 0)
                                                        if !note.matched {
                                                            Image(systemName: "exclamationmark.circle")
                                                                .font(BirdyDesign.caption)
                                                                .foregroundStyle(.orange)
                                                                .help("这条批注的引文未能与 OCR 原文准确匹配")
                                                                .accessibilityLabel("引文未能与原文准确匹配")
                                                        }
                                                        Button {
                                                            saveVocabulary(word: note.quote,
                                                                           meaning: "\(note.title)：\(note.text)",
                                                                           example: note.quote,
                                                                           for: record)
                                                        } label: {
                                                            Image(systemName: "book.closed")
                                                                .font(BirdyDesign.body)
                                                                .foregroundStyle(alreadySaved ? BirdyDesign.accent : BirdyDesign.secondaryText)
                                                                .frame(width: 28, height: 24)
                                                        }
                                                            .disabled(alreadySaved)
                                                            .buttonStyle(.plain)
                                                            .accessibilityLabel(alreadySaved ? "已加入单词本" : "加入单词本")
                                                            .help(alreadySaved ? "已加入单词本" : "加入单词本")
                                                    }
                                                    Text(note.quote.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")).font(BirdyDesign.quote).lineSpacing(1.5).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                                    if note.kind == "vocabulary", let phonetic = note.phonetic, !phonetic.isEmpty {
                                                        Text(phonetic).font(BirdyDesign.phonetic).italic().foregroundStyle(.secondary)
                                                    }
                                                    SelectableVocabularyText(text: note.text,
                                                        savedWords: Set(store.words.filter { $0.recordID == record.id }.map { $0.word.lowercased() }),
                                                        isExplanation: true) { selection in
                                                        saveVocabulary(word: selection, meaning: "", example: record.editedText, for: record)
                                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                                    .background(selectedNoteID == note.id ? BirdyDesign.tint : BirdyDesign.quietSurface, in: RoundedRectangle(cornerRadius: 6))
                                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedNoteID == note.id ? BirdyDesign.accent.opacity(0.35) : .clear, lineWidth: 1))
                                                    .contentShape(RoundedRectangle(cornerRadius: 9))
                                                    .onHover { hovering in selectedNoteID = hovering ? note.id : pinnedNoteID }
                                                    .onTapGesture { pinnedNoteID = note.id; selectedNoteID = note.id }
                                                    .id(note.id)
                                                    .help(note.text)
                                            }
                                        }
                                    }
                                    if let takeaway = record.takeaway, !takeaway.isEmpty {
                                        HStack(alignment: .top, spacing: 7) {
                                            Text("带走").font(BirdyDesign.label).foregroundStyle(.secondary)
                                            Text(takeaway).font(BirdyDesign.emphasis).lineSpacing(1)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                            .background(BirdyDesign.quietSurface, in: RoundedRectangle(cornerRadius: 9))
                                    }
                                    if let latestQuestion = record.turns.last(where: { $0.role == "user" }),
                                       let latestAnswer = record.turns.last(where: { $0.role == "assistant" }) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text("追问补充").font(BirdyDesign.label).foregroundStyle(BirdyDesign.accent)
                                                Spacer()
                                                Button("全部 \(record.turns.filter { $0.role == "user" }.count) 组") { showAllTurns = true }
                                                    .font(BirdyDesign.metadata).buttonStyle(.plain).foregroundStyle(.secondary)
                                            }
                                            Text("问：\(latestQuestion.text)").font(BirdyDesign.caption).foregroundStyle(.secondary).lineLimit(2)
                                            Text(latestAnswer.text).font(BirdyDesign.body).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                            .background(BirdyDesign.quietSurface, in: RoundedRectangle(cornerRadius: 9))
                                            .popover(isPresented: $showAllTurns, arrowEdge: .top) {
                                                ScrollView {
                                                    VStack(alignment: .leading, spacing: 12) {
                                                        ForEach(Array(record.turns.enumerated()), id: \.element.id) { index, turn in
                                                            VStack(alignment: .leading, spacing: 4) {
                                                                Text(turn.role == "user" ? "追问 \((index / 2) + 1)" : "Birdy")
                                                                    .font(BirdyDesign.label).foregroundStyle(turn.role == "user" ? .blue : .secondary)
                                                                Text(turn.text).font(BirdyDesign.body).fixedSize(horizontal: false, vertical: true)
                                                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                                                .background(Color.black.opacity(turn.role == "user" ? 0.035 : 0.02), in: RoundedRectangle(cornerRadius: 8))
                                                        }
                                                    }.padding(14)
                                                }.frame(width: 440, height: 420)
                                            }
                                    }
                                    if !error.isEmpty { Text(error).font(BirdyDesign.body).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                                    VStack(alignment: .leading, spacing: 7) {
                                        Divider()
                                        HStack(spacing: 8) {
                                            Text("来源").font(BirdyDesign.metadata).foregroundStyle(BirdyDesign.secondaryText)
                                            Text(record.sourceApp).font(BirdyDesign.metadata).foregroundStyle(BirdyDesign.secondaryText)
                                            if let url = record.sourceURL, let destination = URL(string: url) {
                                                Link("打开原文", destination: destination).font(BirdyDesign.metadata)
                                            }
                                            Spacer()
                                            if record.pdfPath != nil {
                                                TextField("页", text: $pdfPage).frame(width: 36).onChange(of: pdfPage) { _, value in
                                                    guard var current = store.records.first(where: { $0.id == record.id }), let page = Int(value), page > 0 else { return }
                                                    current.pdfPage = page; store.update(current)
                                                }
                                                Button("PDF 回看") {
                                                    guard let path = record.pdfPath, FileManager.default.fileExists(atPath: path) else { store.statusMessage = "原 PDF 已移动或删除，请重新关联文件"; return }
                                                    openPDF(URL(fileURLWithPath: path), record.pdfAnchor?.page ?? Int(pdfPage), record.pdfAnchor?.quote ?? record.notes.first(where: { $0.matched })?.quote, record.pdfAnchor)
                                                }.font(BirdyDesign.metadata)
                                            }
                                            Button("关联 PDF") { choosePDF(record) }.font(BirdyDesign.metadata)
                                        }
                                        if let url = record.sourceURL {
                                            TextField("来源链接", text: Binding(
                                                get: { store.records.first(where: { $0.id == record.id })?.sourceURL ?? url },
                                                set: { value in
                                                    guard var current = store.records.first(where: { $0.id == record.id }) else { return }
                                                    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    current.sourceURL = cleaned.isEmpty ? nil : cleaned; store.update(current)
                                                }
                                            )).font(BirdyDesign.metadata).textFieldStyle(.roundedBorder).lineLimit(1)
                                        }
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                            .frame(maxWidth: .infinity, alignment: .topLeading).padding(.bottom, 12)
                        }.padding(inset)
                    }
                    .onChange(of: pinnedNoteID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { scrollProxy.scrollTo(id, anchor: .center) }
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    if busy {
                        HStack(spacing: 9) {
                            Text(question).lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ProgressView().controlSize(.small).tint(BirdyDesign.accent)
                            Text("Processing… 请稍等").font(BirdyDesign.heading)
                        }
                        .foregroundStyle(BirdyDesign.accent)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(BirdyDesign.tint, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(BirdyDesign.accent.opacity(0.16), lineWidth: 1))
                    } else {
                        TextField("继续追问…", text: $question).textFieldStyle(.roundedBorder).onSubmit { Task { await ask(record) } }
                        Button("发送") { Task { await ask(record) } }
                            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.padding(.horizontal, inset).padding(.vertical, 12)
            }
        }
    }
    private func selectVisibleRecord() {
        if !visibleRecords.contains(where: { $0.id == store.selectedRecordID }) {
            store.selectedRecordID = visibleRecords.first?.id
        }
    }

    @ViewBuilder private func recordControls(_ record: ReadingRecord, stacked: Bool = false) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 10) {
                recordTopic(record)
                recordPurpose(record)
            }
        } else {
            HStack(spacing: 16) {
                recordTopic(record)
                Spacer(minLength: 12)
                recordPurpose(record)
            }
        }
    }

    private func recordTopic(_ record: ReadingRecord) -> some View {
        TopicEditor(classification: record.classification, restoreAutomatic: { Task { await store.restoreAutomaticClassification(for: record.id) } }) {
            store.setClassification($0, for: record.id)
        }.fixedSize()
    }

    private func recordPurpose(_ record: ReadingRecord) -> some View {
        Picker("用途", selection: Binding(get: { store.records.first(where: { $0.id == record.id })?.purposeOverride ?? "自动" }, set: { value in
            guard var current = store.records.first(where: { $0.id == record.id }) else { return }
            current.purposeOverride = value == "自动" ? nil : value
            store.update(current)
        })) {
            Text("自动：\(record.automaticPurpose ?? "无明显用途")").tag("自动")
            Text("无").tag("")
            ForEach(["词汇积累", "数据描述", "观点展开"], id: \.self) { Text($0).tag($0) }
        }.frame(width: 210).font(BirdyDesign.metadata)
    }
    private func saveVocabulary(word: String, meaning: String, example: String, for record: ReadingRecord, annotationRect: ScreenshotRect? = nil, addAnnotation: Bool = false) {
        let cleanedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedWord.isEmpty else { return }
        let item = VocabularyItem(word: cleanedWord, meaning: meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                                  example: example.trimmingCharacters(in: .whitespacesAndNewlines), recordID: record.id,
                                  sourceApp: record.sourceApp, sourceURL: record.sourceURL)
        store.addWord(item)
        guard let saved = store.words.first(where: {
            $0.recordID == record.id && $0.word.caseInsensitiveCompare(cleanedWord) == .orderedSame
        }) else { return }
        let needsMeaning = saved.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsPhonetic = saved.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        if addAnnotation, !needsMeaning, !needsPhonetic,
           let note = record.notes.first(where: { $0.kind == "vocabulary" && $0.quote.caseInsensitiveCompare(cleanedWord) == .orderedSame }) {
            pinnedNoteID = note.id; selectedNoteID = note.id
            store.statusMessage = "已定位「\(cleanedWord)」的原文解读"
            return
        }
        guard needsMeaning || needsPhonetic || annotationRect != nil || addAnnotation else {
            store.statusMessage = "已加入单词本：\(cleanedWord)"
            return
        }
        guard enrichingVocabularyIDs.insert(saved.id).inserted else { return }
        store.statusMessage = annotationRect == nil
            ? "已保存「\(cleanedWord)」，正在补充释义与音标…"
            : "已保存「\(cleanedWord)」，正在生成词语注释与音标…"
        if addAnnotation { pendingAnnotations[saved.id] = (record.id, cleanedWord) }
        Task { await enrichVocabulary(id: saved.id, word: cleanedWord, example: item.example, record: record, annotationRect: annotationRect, addAnnotation: addAnnotation) }
    }
    private func enrichVocabulary(id: UUID, word: String, example: String, record: ReadingRecord, annotationRect: ScreenshotRect?, addAnnotation: Bool) async {
        defer { enrichingVocabularyIDs.remove(id); pendingAnnotations.removeValue(forKey: id) }
        let relevantNotes = record.notes.filter { $0.quote.localizedCaseInsensitiveContains(word) || word.localizedCaseInsensitiveContains($0.quote) || $0.text.localizedCaseInsensitiveContains(word) }
        let notesContext = relevantNotes.map { "\($0.quote) — \($0.title)：\($0.text)" }.joined(separator: "\n")
        let notesForPrompt = notesContext.isEmpty ? "无" : notesContext
        let prompt = "请为一位 IELTS 7 分左右的英语学习者分析词条，并严格返回 JSON 对象，不要 markdown 代码围栏：{\"meaning\":\"单词本用的简洁中文释义与必要用法\",\"phonetic\":\"目标词或短语的英式 IPA，使用 / /，不确定时留空\",\"title\":\"一条短的语言观察标题\",\"annotation\":\"分段说明语境作用、普通说法对比和使用提示，通常3-4句\"}。meaning 说明本句中的准确意思；仅在值得学习时补充词性、语义细差、搭配或可迁移用法。phonetic 只写音标，不写读音提示；短语可给出自然连读的 IPA。meaning 在准确释义后可加一句有用的普通表达对比。annotation 必须给出自然且意思尽量接近的普通英文表达，明确标为“普通说法”，说明当前表达在准确性、强度、语气、语域或意象上的具体差别，并给出何时适合使用的提示；不把更复杂等同于更好，语义不同要明说，避免无依据推断。用换行分开解释、对比和使用提示。annotation 需要说清这个词在此处具体做了什么、它的选择如何影响句意或读者感受；不能只重复释义，也不要作无依据的作者意图推断。避免基础英语教学、泛泛评价和堆术语。若是人名或 OCR 误识别，不要臆造释义或音标，说明无法可靠释义并将 phonetic 留空。\n词条：\(word)\n当前句子：\(example)\n相关精读观察：\(notesForPrompt)"
        do {
            let completion = try await ReadingAPI.complete(prompt: prompt, preferences: store.preferences, apiKey: store.apiKey)
            let json = completion.firstIndex(of: "{").flatMap { start in completion.lastIndex(of: "}").map { String(completion[start...$0]) } } ?? completion
            let draft = try JSONDecoder().decode(WordAnnotationDraft.self, from: Data(json.utf8))
            if addAnnotation && draft.annotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw APIError.badResponse("未返回语境解读，请再次选中词语重试")
            }
            guard var latestWord = store.words.first(where: { $0.id == id }) else { return }
            if latestWord.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
               !draft.phonetic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                latestWord.phonetic = draft.phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if latestWord.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                latestWord.meaning = draft.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            store.updateWord(latestWord)
            if (addAnnotation || annotationRect != nil), !draft.annotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               var latestRecord = store.records.first(where: { $0.id == record.id }), latestRecord.editedText == record.editedText {
                let existingNote = latestRecord.notes.first { note in
                    note.kind == "vocabulary" && note.quote.caseInsensitiveCompare(word) == .orderedSame &&
                    (annotationRect == nil || note.screenshotRects.contains { rect in
                        guard let annotationRect else { return false }
                        return abs(rect.x - annotationRect.x) < 0.001 && abs(rect.y - annotationRect.y) < 0.001 &&
                        abs(rect.width - annotationRect.width) < 0.001 && abs(rect.height - annotationRect.height) < 0.001
                    })
                }
                let note = existingNote ?? ReadingNote(quote: word, kind: "vocabulary",
                                                       title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       text: draft.annotation.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       phonetic: draft.phonetic.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       matched: true, screenshotRects: annotationRect.map { [$0] } ?? ReadingAPI.rects(for: word, lines: latestRecord.ocrLines))
                if existingNote == nil {
                    latestRecord.notes.append(note)
                } else if let index = latestRecord.notes.firstIndex(where: { $0.id == existingNote?.id }),
                          latestRecord.notes[index].phonetic?.isEmpty != false {
                    latestRecord.notes[index].phonetic = draft.phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                latestWord.noteID = note.id
                store.updateWord(latestWord)
                store.update(latestRecord)
                pinnedNoteID = note.id
                selectedNoteID = note.id
                store.statusMessage = existingNote == nil
                    ? "「\(word)」已加入单词本，并补充了原文解读"
                    : "「\(word)」已加入单词本，已定位到原文解读"
            } else {
                store.statusMessage = "单词释义已补全：\(word)"
            }
        } catch {
            store.statusMessage = addAnnotation
                ? "「\(word)」已保存，但解读生成失败；可再次选中并点击按钮重试。"
                : annotationRect == nil
                ? "「\(word)」已保存，但释义或音标补全失败；词条仍在单词本中，可稍后编辑。"
                : "「\(word)」已保存，但注释或音标生成失败；词条仍在单词本中。"
        }
    }
    private func undoVocabulary(_ word: String, for record: ReadingRecord) {
        guard let item = store.words.first(where: {
            $0.recordID == record.id && $0.word.caseInsensitiveCompare(word) == .orderedSame
        }) else { return }
        store.deleteWord(item.id)
        store.statusMessage = "已从单词本移除「\(item.word)」，截图注释保留"
    }
    private func binding(_ record: ReadingRecord, _ keyPath: WritableKeyPath<ReadingRecord, String>) -> Binding<String> {
        Binding(get: { store.records.first(where: { $0.id == record.id })?[keyPath: keyPath] ?? "" }, set: { var r = store.records.first(where: { $0.id == record.id }) ?? record; r[keyPath: keyPath] = $0; store.update(r) })
    }
    private func noteQuoteBinding(_ record: ReadingRecord, _ note: ReadingNote) -> Binding<String> {
        Binding(get: { store.records.first(where: { $0.id == record.id })?.notes.first(where: { $0.id == note.id })?.quote ?? note.quote }, set: { value in
            guard var current = store.records.first(where: { $0.id == record.id }), let i = current.notes.firstIndex(where: { $0.id == note.id }) else { return }
            current.notes[i].quote = value
            let count = current.editedText.components(separatedBy: value).count - 1
            current.notes[i].matched = !value.isEmpty && count == 1
            if current.notes[i].matched, current.editedText == current.ocrText {
                current.notes[i].screenshotRects = ReadingAPI.rects(for: value, lines: current.ocrLines)
            } else { current.notes[i].screenshotRects = [] }
            store.update(current)
        })
    }
    private func choosePDF(_ record: ReadingRecord) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { store.statusMessage = "无法读取这份 PDF"; return }
        let page = min(max(Int(pdfPage) ?? 1, 1), document.pageCount)
        var changed = store.records.first { $0.id == record.id } ?? record
        changed.pdfPath = url.path; changed.pdfPage = page; changed.pdfAnchor = nil
        store.update(changed); pdfPage = String(page)
        openPDF(url, changed.pdfPage, changed.notes.first(where: { $0.matched })?.quote, changed.pdfAnchor)
    }
    private func ask(_ record: ReadingRecord) async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        busy = true; error = ""; defer { busy = false }
        do {
            var r = store.records.first { $0.id == record.id } ?? record
            let context = "当前截图 OCR 原文：\n\(r.editedText)\n\n此前精读解释：\n\(r.explanation)\n\n用户问题：\n\(text)"
            let result = try await ReadingAPI.complete(prompt: context, history: r.turns, preferences: store.preferences, apiKey: store.apiKey)
            r.turns += [ChatTurn(role: "user", text: text), ChatTurn(role: "assistant", text: result)]; store.update(r); question = ""
        } catch { self.error = "追问失败：\(error.localizedDescription)" }
    }
}

private struct VocabularyEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var word: String
    @State private var phonetic: String
    @State private var meaning: String
    @State private var example: String
    let onSave: (String, String, String, String) -> Void
    init(word: String, phonetic: String, meaning: String, example: String, onSave: @escaping (String, String, String, String) -> Void) {
        _word = State(initialValue: word)
        _phonetic = State(initialValue: phonetic)
        _meaning = State(initialValue: meaning)
        _example = State(initialValue: example)
        self.onSave = onSave
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("加入单词本").font(BirdyDesign.section)
            TextField("单词或短语", text: $word).font(BirdyDesign.word)
            TextField("IPA 音标", text: $phonetic).font(BirdyDesign.phonetic)
            TextField("中文释义 / 用法", text: $meaning, axis: .vertical).lineLimit(2...4)
            VStack(alignment: .leading, spacing: 5) {
                Text("原文例句").font(BirdyDesign.label).foregroundStyle(.secondary)
                TextEditor(text: $example).font(BirdyDesign.example).frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
            }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存词条") {
                let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return }
                onSave(cleaned, phonetic.trimmingCharacters(in: .whitespacesAndNewlines), meaning.trimmingCharacters(in: .whitespacesAndNewlines), example.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
            }.keyboardShortcut(.defaultAction).disabled(word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(22).frame(width: 520)
    }
}

struct VocabularyPane: View {
    @ObservedObject var store: AppStore
    var initialSearch: String = ""
    let openRecord: (UUID) -> Void
    @State private var search = ""
    @State private var exportURL: URL?
    @State private var editingWord: VocabularyItem?
    @State private var topicFilter = "全部"
    @State private var selectedGraphWordID: UUID?
    @State private var recallMode = false
    @State private var revealedCards: Set<UUID> = []
    @State private var shuffledIDs: [UUID] = []
    private var recallWords: [VocabularyItem] {
        let ranks = Dictionary(uniqueKeysWithValues: shuffledIDs.enumerated().map { ($0.element, $0.offset) })
        return filtered.sorted { (ranks[$0.id] ?? Int.max) < (ranks[$1.id] ?? Int.max) }
    }
    private var filtered: [VocabularyItem] { store.words.filter {
        (topicFilter == "全部" || ($0.classification?.category ?? "待分类") == topicFilter)
        && $0.matchesSearch(search)
    } }
    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = geometry.size.width < 1000 ? 20 : 28
            HStack(spacing: 0) {
                BirdyCategorySidebar(categories: TopicClassification.categories + ["待分类"], selection: $topicFilter) { name in
                    store.words.filter { name == "全部" || ($0.classification?.category ?? "待分类") == name }.count
                }.frame(width: geometry.size.width < 1000 ? 164 : 190)
                Divider()
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        BirdyLibraryTitle(title: topicFilter == "全部" ? "单词本" : topicFilter, count: "\(filtered.count) 条")
                        Spacer(minLength: 0)
                        BirdyLibrarySearch(placeholder: "搜索词条、释义或例句", text: $search).frame(maxWidth: 300)
                        Button(recallMode ? "退出回忆" : "一键隐藏") {
                            recallMode.toggle(); revealedCards.removeAll(); shuffledIDs = filtered.map(\.id)
                        }.keyboardShortcut("h", modifiers: [.command, .shift])
                            .help("隐藏释义与例句，逐张揭晓 · ⌘⇧H")
                        Menu {
                            Button("导出 CSV") { do { exportURL = try store.exportWords(); store.statusMessage = "已导出：\(exportURL!.path)" } catch { store.statusMessage = "导出失败：\(error.localizedDescription)" } }
                            Button("完整备份 ZIP") { exportBackup() }
                            Divider()
                            Button("刷新表达关联") { Task { await store.refreshExpressionLinks(force: true) } }
                                .disabled(store.refreshingExpressionLinks)
                            if !store.expressionLinks.dismissed.isEmpty {
                                Button("恢复隐藏关联") { store.restoreDismissedExpressionLinks() }
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 20, height: 16) }
                            .fixedSize().accessibilityLabel("单词本更多操作").help("导出、备份与表达关联维护")
                    }.padding(.horizontal, inset).padding(.vertical, 14)
                    Divider()
                    if recallMode {
                        HStack {
                            Text("先回忆意思或造句，点击词条揭晓答案。")
                                .font(BirdyDesign.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("打乱") { shuffledIDs = filtered.map(\.id).shuffled(); revealedCards.removeAll() }
                                .disabled(filtered.count < 2)
                        }.padding(.horizontal, inset).padding(.vertical, 10)
                    }
                    if store.refreshingExpressionLinks || !store.expressionLinkError.isEmpty {
                        HStack(spacing: 10) {
                            if store.refreshingExpressionLinks { ProgressView().controlSize(.small) }
                            Text(store.expressionLinkError.isEmpty ? store.expressionLinkProgress : store.expressionLinkError)
                                .font(BirdyDesign.caption).foregroundStyle(store.expressionLinkError.isEmpty ? Color.secondary : Color.red).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, inset).padding(.vertical, 10)
                    }
            if recallMode {
                ScrollView {
                    if filtered.isEmpty {
                        ContentUnavailableView("没有找到词条", systemImage: "character.book.closed", description: Text("试试其他搜索词，或切换到全部话题。"))
                            .padding(.top, 50)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                        ForEach(recallWords) { item in
                            Button {
                                if revealedCards.contains(item.id) { revealedCards.remove(item.id) }
                                else { revealedCards.insert(item.id) }
                            } label: {
                                VStack(alignment: revealedCards.contains(item.id) ? .leading : .center, spacing: 12) {
                                    Text(item.word).font(BirdyDesign.word).foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: revealedCards.contains(item.id) ? .leading : .center)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if revealedCards.contains(item.id) {
                                        if let phonetic = item.phonetic, !phonetic.isEmpty {
                                            Text(phonetic).font(BirdyDesign.phonetic).foregroundStyle(.secondary)
                                        }
                                        Text(item.meaning).font(BirdyDesign.body).foregroundStyle(.primary).lineSpacing(3)
                                        if !item.example.isEmpty {
                                            BirdyExampleText(text: item.example)
                                        }
                                    }
                                }.padding(20).frame(maxWidth: .infinity, minHeight: 150)
                                    .background(BirdyDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                                .accessibilityLabel(item.word)
                                .accessibilityValue(revealedCards.contains(item.id) ? "答案已显示" : "答案已隐藏")
                                .help(revealedCards.contains(item.id) ? "点击收起答案" : "点击揭晓答案")
                        }
                    }.padding(inset)
                }
            } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "单词本还是空的" : "没有找到词条", systemImage: "character.book.closed", description: Text(store.words.isEmpty ? "在精读记录里点「加入单词本」，只保存你想复习的表达。" : "试试其他搜索词，或将主题筛选切换为全部话题。"))
                            .padding(.top, 50)
                    }
                    ForEach(filtered) { item in
                        VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 9) {
                                Button {
                                    selectedGraphWordID = selectedGraphWordID == item.id ? nil : item.id
                                } label: {
                                    HStack(spacing: 9) {
                                        Text(item.word).font(BirdyDesign.word).foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Image(systemName: "point.3.connected.trianglepath.dotted").font(BirdyDesign.caption)
                                        Image(systemName: selectedGraphWordID == item.id ? "chevron.up" : "chevron.down").font(BirdyDesign.metadata)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).help("展开或收起原文表达关联")
                                    .accessibilityLabel("\(item.word)，原文表达关联")
                                if let phonetic = item.phonetic, !phonetic.isEmpty {
                                    Text(phonetic).font(BirdyDesign.phonetic).italic().foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                if !item.meaning.isEmpty {
                                    Text(item.meaning).font(BirdyDesign.body).foregroundStyle(.primary).lineSpacing(3).textSelection(.enabled)
                                }
                                if !item.example.isEmpty {
                                    BirdyExampleText(text: item.example).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 10) {
                                Button { editingWord = item } label: {
                                    Image(systemName: "pencil").font(BirdyDesign.caption).foregroundStyle(.secondary)
                                }.buttonStyle(.plain).help("编辑词条").accessibilityLabel("编辑词条")
                                Button(role: .destructive) { store.deleteWord(item.id) } label: {
                                    Image(systemName: "trash").font(BirdyDesign.caption).foregroundStyle(.secondary)
                                }.buttonStyle(.plain).help("删除词条 · ⌘Z 撤回").accessibilityLabel("删除词条")
                            }.fixedSize(horizontal: true, vertical: false).padding(.top, 3)
                        }
                                HStack(alignment: .bottom, spacing: 14) {
                                TopicEditor(classification: item.classification, restoreAutomatic: { store.restoreWordClassification(item.id) }) { topic in
                                    guard var current = store.words.first(where: { $0.id == item.id }) else { return }
                                    current.classification = topic; current.classificationIsManual = true
                                    store.updateWord(current)
                                }
                                    Spacer(minLength: 12)
                                    if let id = item.recordID {
                                        Button("回到精读记录 ↗") { openRecord(id) }.buttonStyle(.plain).font(BirdyDesign.metadata)
                                    }
                                    if let source = item.sourceURL,
                                       let target = CaptureService.chromeTextURL(sourceURL: source, quote: item.example.isEmpty ? item.word : item.example) {
                                        Link("打开原文 ↗", destination: target).font(BirdyDesign.metadata)
                                    }
                                }.foregroundStyle(BirdyDesign.secondaryText).padding(.top, 4)
                            if selectedGraphWordID == item.id {
                                ExpressionGraphView(store: store, word: item, openRecord: openRecord)
                                    .padding(.top, 14)
                            }
                        }.padding(.vertical, 24)
                        Divider()
                    }
                }.padding(.horizontal, inset)
            }
            }
        }
            }
        }
        .onChange(of: topicFilter) { _, _ in revealedCards.removeAll(); shuffledIDs = filtered.map(\.id) }
        .onChange(of: search) { _, _ in revealedCards.removeAll(); shuffledIDs = filtered.map(\.id) }
        .onAppear { search = initialSearch }
        .onChange(of: initialSearch) { _, value in search = value; topicFilter = "全部" }
        .sheet(item: $editingWord) { item in
            VocabularyEntryEditor(word: item.word, phonetic: item.phonetic ?? "", meaning: item.meaning, example: item.example) { word, phonetic, meaning, example in
                var edited = store.words.first { $0.id == item.id } ?? item
                edited.word = word; edited.phonetic = phonetic.isEmpty ? nil : phonetic; edited.meaning = meaning; edited.example = example
                store.updateWord(edited)
            }
        }
    }
    private func exportBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Birdy备份.zip"; panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportBackup(to: url); store.statusMessage = "已创建完整备份：\(url.path)" }
        catch { store.statusMessage = "备份失败：\(error.localizedDescription)" }
    }
}

struct SettingsPane: View {
    @ObservedObject var store: AppStore
    @State private var keyDraft = ""
    var body: some View {
        Form {
            Text("精读模型（默认 DeepSeek Flash）").font(BirdyDesign.section)
            TextField("API Base URL", text: $store.preferences.endpoint)
            TextField("模型名称", text: $store.preferences.model)
            SecureField("API Key（保存到 macOS 钥匙串）", text: $keyDraft)
            Toggle("启动应用时显示主窗口", isOn: $store.preferences.showWindowOnLaunch)
            Button("保存设置") { store.apiKey = keyDraft; store.savePreferences(); store.statusMessage = "设置已保存" }
            Divider()
            HStack {
                Button("启用登录时启动") { do { try SMAppService.mainApp.register(); store.statusMessage = "已启用登录时启动" } catch { store.statusMessage = "启用失败：\(error.localizedDescription)" } }
                Button("关闭登录时启动") { do { try SMAppService.mainApp.unregister(); store.statusMessage = "已关闭登录时启动" } catch { store.statusMessage = "关闭失败：\(error.localizedDescription)" } }
                Text("当前状态：\(SMAppService.mainApp.status == .enabled ? "已启用" : "未启用")")
            }
            Divider()
            Text("⌘4：有选中文字时直接精读，没有选中文字时截图框选。读取选区需要辅助功能权限；截图需要屏幕录制权限。").font(BirdyDesign.caption).foregroundStyle(BirdyDesign.secondaryText)
            Button("打开屏幕录制权限设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            Text("来源：Chrome 标签网址会尝试自动读取，首次使用可能请求自动化权限。Preview 文件请在精读记录中手动关联 PDF 并填写页码。").font(BirdyDesign.caption).foregroundStyle(BirdyDesign.secondaryText)
        }.formStyle(.grouped).font(BirdyDesign.control).padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading).textFieldStyle(.roundedBorder)
            .onAppear { keyDraft = store.apiKey }
    }
    private func guideline(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(BirdyDesign.heading)
            Text(text).font(BirdyDesign.body).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

}


struct LearningGuidePane: View {
    var body: some View {
        Form {
            Section {
                Text("从读懂到会用").font(BirdyDesign.section)
                guideline("主动回忆", "单词本先隐藏答案，尝试回忆意思或造句，再单张揭晓核对。熟悉感不等于能够主动使用。")
                Link("研究：回忆词汇与跟读的比较", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/23681928/")!)
                guideline("产出与发现缺口", "看文章中文论证树时先组织英文，再揭晓原段，发现搭配、句法或语气上的缺口。输出假说提供理论依据，具体效果受任务和反馈质量影响。")
                Link("研究：Swain 的输出与注意研究", destination: URL(string: "https://doi.org/10.1093/APPLIN/16.3.371")!)
                guideline("间隔与迁移", "分散在不同日期回忆，并换情境使用表达。当前支持话题筛选与中英切换；自动间隔排程尚未实现。")
                Link("研究：二语词汇训练综述", destination: URL(string: "https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/review-of-laboratory-studies-of-adult-second-language-vocabulary-training/18F0A5D1FFC829CE05931B2EEE83124A")!)
            }
            Section {
                Text("精读分析准则").font(BirdyDesign.section)
                VStack(alignment: .leading, spacing: 10) {
                    guideline("筛选", "以 IELTS 7 左右为基准，通常选 1–3 处真正值得学习的表达，也可以不生成观察。不为凑数量分析基础连接词、常规语法或显而易见的意思。")
                    guideline("讲解", "先说明语境意思，再解释具体的句子结构、语法、用词或语气。标题准确但不堆砌术语；充分讲解，分段呈现。")
                    guideline("对比", "给出自然、意思接近的普通英文说法，对比原文在准确性、限定、强度、焦点、节奏、语域或意象上的差别。没有实质差别，就不硬造优势。")
                    guideline("迁移", "说明什么情境适合使用这个表达，帮助从熟悉的说法联想到替代写法。更复杂不等于更好，语义不完全相同时明确说明。")
                    guideline("证据", "以选中原文为依据，准确引用；不补造背景、不猜作者心理，OCR 不清楚时降低判断强度。")
                    guideline("词汇", "除搭配、少见义项和语义细差，也解读影响形状、质感或画面感的具体词，即使句法简单。例如 encased 的完整包裹义、chequered 的交错方格图案，说明语境含义及与 covered、patterned 等常见说法的区别。通常 0–3 条，不按数量硬凑，也不强求每个词都有修辞优势。用户主动选中的单词或词组仍可保存；释义按当前语境解释，音标不确定时留空。")
                }.padding(.vertical, 8)
                Text("本段线索解释这段在说什么；带走保留一个可记住的表达或写法，避免重复。")
                    .font(BirdyDesign.caption).foregroundStyle(BirdyDesign.secondaryText)
            }


        }.formStyle(.grouped).font(BirdyDesign.body).padding(24)
    }
    private func guideline(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(BirdyDesign.heading)
            Text(text).font(BirdyDesign.body).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

}
