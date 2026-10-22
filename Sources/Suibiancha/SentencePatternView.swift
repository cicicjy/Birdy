import SwiftUI

struct SentencePatternPane: View {
    @ObservedObject var store: AppStore
    let openRecord: (UUID) -> Void
    @State private var category = "全部"
    @State private var search = ""
    @State private var editingEntry: SentencePattern?
    private var all: [SentencePattern] { store.visibleSentencePatterns }
    private var filtered: [SentencePattern] {
        all.filter { entry in
            (category == "全部" || entry.category == category) && (search.isEmpty || [entry.quote, entry.pattern, entry.category].contains { $0.localizedCaseInsensitiveContains(search) })
        }.sorted { lhs, rhs in
            let left = store.records.first { $0.id == lhs.recordID }?.createdAt ?? .distantPast
            let right = store.records.first { $0.id == rhs.recordID }?.createdAt ?? .distantPast
            return left == right ? lhs.id < rhs.id : left > right
        }
    }
    var body: some View {
        GeometryReader { geometry in
        let compact = geometry.size.width < 1000
        HStack(spacing: 0) {
            BirdyCategorySidebar(title: "表达功能", categories: SentencePatternDiscovery.categories, selection: $category) { name in
                name == "全部" ? all.count : all.filter { $0.category == name }.count
            }.frame(width: compact ? 164 : 190)
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    BirdyLibraryTitle(title: category == "全部" ? "句式库" : category, count: "\(filtered.count) 条")
                    Spacer(minLength: 0)
                    BirdyLibrarySearch(placeholder: "搜索句式或原句", text: $search).frame(maxWidth: 300)
                    Button("刷新历史句式") { Task { await store.refreshSentencePatterns(force: true) } }
                        .disabled(store.refreshingSentencePatterns)
                }.padding(.horizontal, compact ? 20 : 28).padding(.vertical, 14)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.refreshingSentencePatterns {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text(store.sentencePatternProgress).font(BirdyDesign.caption).foregroundStyle(.secondary)
                            }.padding(.top, 12)
                        }
                        if !store.sentencePatternError.isEmpty {
                            Text(store.sentencePatternError).font(BirdyDesign.caption).foregroundStyle(.red)
                                .textSelection(.enabled).padding(.top, 12)
                        }
                        if filtered.isEmpty {
                            ContentUnavailableView(store.refreshingSentencePatterns ? "正在从原句中提炼" : "还没有符合条件的句式", systemImage: "text.quote", description: Text(search.isEmpty ? "这一类尚无合适的原文实例时会保持为空。新增摘录后会自动补充，也可以刷新历史句式。" : "试试其他搜索词，或选择全部分类。"))
                                .padding(.vertical, 40)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(filtered) { entry in
                                    patternRow(entry).padding(.vertical, 20)
                                    Divider()
                                }
                            }.padding(.top, 8)
                        }
                    }.padding(compact ? 20 : 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        }
        .sheet(item: $editingEntry) { entry in
            SentencePatternEditor(entry: entry) { pattern, category in
                store.editSentencePattern(entry, pattern: pattern, category: category)
            }
        }
    }
    private func patternRow(_ entry: SentencePattern) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                Text(TextFlow.prose(entry.pattern)).font(BirdyDesign.word).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button { editingEntry = entry } label: {
                        Image(systemName: "pencil").font(BirdyDesign.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("编辑句式").accessibilityLabel("编辑句式")
                    Button(role: .destructive) { store.deleteSentencePattern(entry) } label: {
                        Image(systemName: "trash").font(BirdyDesign.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("删除句式 · ⌘Z 撤回").accessibilityLabel("删除句式")
                }.fixedSize(horizontal: true, vertical: false).padding(.top, 3)
            }
            BirdyExampleText(text: entry.quote).textSelection(.enabled)
            Button("回到精读记录") { openRecord(entry.recordID) }
                .buttonStyle(.plain).font(BirdyDesign.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SentencePatternEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: String
    @State private var category: String
    let entry: SentencePattern
    let onSave: (String, String) -> Void
    init(entry: SentencePattern, onSave: @escaping (String, String) -> Void) {
        self.entry = entry; self.onSave = onSave
        _pattern = State(initialValue: TextFlow.prose(entry.pattern))
        _category = State(initialValue: entry.category)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑句式").font(BirdyDesign.section)
            TextField("核心句式", text: $pattern, axis: .vertical).font(BirdyDesign.word)
                .lineLimit(2...4).accessibilityLabel("核心句式")
            Picker("分类", selection: $category) {
                ForEach(SentencePatternDiscovery.categories, id: \.self) { Text($0).tag($0) }
            }
            BirdyExampleText(text: entry.quote).textSelection(.enabled)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存句式") { onSave(pattern, category); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 520)
    }
}
