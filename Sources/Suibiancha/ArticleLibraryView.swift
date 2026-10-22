import SwiftUI

struct ArticlePracticePane: View {
    @ObservedObject var store: AppStore
    @ObservedObject var library: ArticlePracticeLibrary
    @State private var selectedID = ""
    @State private var category = "全部"
    @State private var urlDraft = ""
    @State private var inputError = ""
    @State private var importSession: ArticleImportSession?

    private var categories: [String] {
        let available = Set(library.documents.map { $0.classification?.category ?? "待分类" })
        return TopicClassification.categories.filter { available.contains($0) } + (available.contains("待分类") ? ["待分类"] : [])
    }
    private var filtered: [ArticlePracticeDocument] {
        library.documents.filter { category == "全部" || ($0.classification?.category ?? "待分类") == category }
    }
    private var current: ArticlePracticeDocument? { filtered.first(where: { $0.id == selectedID }) ?? filtered.first }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                librarySidebar
                    .frame(width: geometry.size.width >= 1000 ? 240 : 210)
                    .background(Color.primary.opacity(0.035))
                Divider()
                if let current {
                    ArticlePracticeReader(document: current).id(current.id)
                } else {
                    ContentUnavailableView("这个话题还没有文章", systemImage: "text.bubble", description: Text("在左侧添加文章，生成中文论证树。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.padding(.top, 12)
        }
        .onChange(of: category) { _, _ in
            if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id ?? "" }
        }
        .sheet(item: $importSession) { session in
            ArticleImportView(session: session, store: store, sourceURL: urlDraft.trimmingCharacters(in: .whitespacesAndNewlines), dismiss: { importSession = nil }) { document in
                try library.add(document)
                category = "全部"
                selectedID = document.id
                importSession = nil
            }
        }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("文章库").font(BirdyDesign.heading)
                    Spacer()
                    Text("\(filtered.count) 篇").font(BirdyDesign.metadata).foregroundStyle(.secondary)
                }
                Picker("话题", selection: $category) {
                    Text("全部话题").tag("全部")
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: .infinity)
                    .accessibilityLabel("筛选文章话题")
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filtered) { article in
                        Button { selectedID = article.id } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(article.title).font(BirdyDesign.emphasis)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(article.classification?.category ?? "待分类")
                                    .font(BirdyDesign.metadata).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(current?.id == article.id ? Color.accentColor.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityValue(current?.id == article.id ? "已选择" : "未选择")
                    }
                    if filtered.isEmpty {
                        Text("暂无文章").font(BirdyDesign.caption).foregroundStyle(.secondary).padding(12)
                    }
                }.padding(8)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("添加文章").font(BirdyDesign.heading)
                TextField("粘贴网页链接", text: $urlDraft)
                    .textFieldStyle(.roundedBorder).onSubmit(beginImport)
                    .accessibilityLabel("文章网页链接")
                Button("读取全文", action: beginImport)
                    .disabled(urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !inputError.isEmpty || !library.error.isEmpty {
                    Text(inputError.isEmpty ? library.error : inputError)
                        .font(BirdyDesign.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(16)
        }
    }

    private func beginImport() {
        inputError = ""
        let value = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ArticlePracticeDocument.webURL(value), ArticleWebReader.allowed(url) else {
            inputError = "请粘贴完整的公开文章链接，例如 https://example.com/article。"
            return
        }
        if let existing = library.existing(value) {
            category = "全部"; selectedID = existing.id
            inputError = "这篇文章已在文章库中，已为你打开。"
            return
        }
        let session = ArticleImportSession()
        importSession = session
        session.read(url)
    }
}

private struct ArticleImportView: View {
    @ObservedObject var session: ArticleImportSession
    @ObservedObject var store: AppStore
    let sourceURL: String
    let dismiss: () -> Void
    let save: (ArticlePracticeDocument) throws -> Void
    @State private var pastedText = ""
    @State private var showPaste = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("添加文章").font(BirdyDesign.section)
                Spacer()
                Button(session.busy ? "取消" : "关闭") { session.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text(sourceURL).font(BirdyDesign.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Divider()
            if !session.status.isEmpty {
                HStack { ProgressView().controlSize(.small); Text(session.status).font(BirdyDesign.body) }
            }
            if !session.error.isEmpty {
                Text(session.error).font(BirdyDesign.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let article = session.article {
                HStack {
                    Text("已读取 \(article.paragraphs.count) 段正文").font(BirdyDesign.heading)
                    Spacer()
                    Text(article.publisher).font(BirdyDesign.metadata).foregroundStyle(.secondary)
                }
                Text("请核对正文开头与结尾，确认没有被登录或订阅提示截断。解析将使用设置中配置的模型。")
                    .font(BirdyDesign.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !article.title.isEmpty { Text(article.title).font(BirdyDesign.section) }
                        ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            VStack(alignment: .leading, spacing: 6) {
                                BirdyExampleText(text: paragraph, isReference: true).textSelection(.enabled)
                                Text("第 \(index+1) 段").font(BirdyDesign.metadata).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Button("改用粘贴全文") { showPaste.toggle() }.disabled(session.busy)
                    Spacer()
                    Button("解析并加入表达") { session.analyse(preferences: store.preferences, apiKey: store.apiKey, save: save) }
                        .disabled(session.busy)
                }
            } else if !session.busy {
                Text("网页无法直接读取时，可以粘贴英文全文。原段落将作为英文参考保留。")
                    .font(BirdyDesign.caption).foregroundStyle(.secondary)
                if !showPaste { Button("粘贴英文全文") { showPaste = true } }
                Spacer(minLength: 0)
            } else {
                Spacer()
            }
            if showPaste {
                Text("英文全文（段落之间保留空行）").font(BirdyDesign.heading)
                TextEditor(text: $pastedText).font(BirdyDesign.quote).frame(minHeight: 130, maxHeight: 210)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.12)))
                    .accessibilityLabel("粘贴完整英文正文")
                Button("使用这份正文") {
                    do { try session.usePastedText(pastedText, url: sourceURL); showPaste = false }
                    catch { session.error = error.localizedDescription }
                }.disabled(session.busy || pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 780, height: 700)
            .font(BirdyDesign.control).onDisappear { session.cancel() }
    }
}
