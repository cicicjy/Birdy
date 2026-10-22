import SwiftUI

struct ArticlePracticeReader: View {
    let document: ArticlePracticeDocument
    @State private var english: Set<String> = []
    @State private var selectedSection = "question"
    @State private var showCoverage = false

    private var allEnglish: Bool {
        return english.count == document.treeParagraphs.count
    }

    var body: some View { article(document) }

    private func article(_ document: ArticlePracticeDocument) -> some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780
            let inset: CGFloat = wide ? 28 : 20
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Menu("结构导航") {
                            Button("中心问题") { proxy.scrollTo("question", anchor: .top) }
                            ForEach(document.groups) { branch in
                                Button(branch.label) { proxy.scrollTo(branch.id, anchor: .top) }
                            }
                        }.fixedSize()
                        Spacer(minLength: 0)
                        Button(allEnglish ? "全部恢复中文" : "全部切换为英文") {
                            english = allEnglish ? [] : Set(document.treeParagraphs.map(\.id))
                        }
                        if let url = ArticlePracticeDocument.webURL(document.source) {
                            Link("打开原文", destination: url).font(BirdyDesign.caption)
                        }
                    }.padding(.horizontal, inset).padding(.vertical, 12)
                    Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(document.title).font(BirdyDesign.section)
                                    Text(document.englishTitle ?? document.title)
                                        .font(BirdyDesign.example).foregroundStyle(.secondary)
                                    Text("\(document.publisher) · \(document.author) · \(document.coverage.bodyParagraphs) 段 · \(document.coverage.bodyWords) 词")
                                        .font(BirdyDesign.metadata).foregroundStyle(.secondary)
                                    Text("先看中文，自己表述英文。点击段落查看英文原段，再点恢复中文。")
                                        .font(BirdyDesign.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("中心问题").font(BirdyDesign.heading)
                                    paragraph(document.root)
                                }.id("question")
                                ForEach(document.groups) { branch in
                                    branchView(branch, wide: wide).id(branch.id)
                                }
                                DisclosureGroup(isExpanded: $showCoverage) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("依照原文顺序逐段定位。\(document.coverage.scope)")
                                            .font(BirdyDesign.caption).foregroundStyle(.secondary)
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), alignment: .leading)], alignment: .leading, spacing: 10) {
                                            ForEach(document.paragraphs) { item in
                                                Button("第 \(item.paragraph) 段") {
                                                    if let branch = document.groups.first(where: { ([$0.main] + $0.evidence).contains(where: { $0.id == item.id }) }) {
                                                        selectedSection = branch.id
                                                    } else { selectedSection = "question" }
                                                    proxy.scrollTo(item.id, anchor: .top)
                                                }.buttonStyle(.plain).font(BirdyDesign.metadata).foregroundStyle(.secondary)
                                                    .help(item.zh)
                                            }
                                        }
                                    }.padding(.top, 10)
                                } label: {
                                    Text("原文段落覆盖 · \(document.coverage.coveredParagraphs) / \(document.coverage.bodyParagraphs) 段")
                                        .font(BirdyDesign.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                                HStack(alignment: .top, spacing: 12) {
                                    Text("中文为完整段落译文；英文保留转载全文原句。")
                                        .font(BirdyDesign.metadata).foregroundStyle(.secondary)
                                    if let url = ArticlePracticeDocument.webURL(document.readback) {
                                        Link("核对英文转载", destination: url).font(BirdyDesign.caption)
                                    }
                                }
                            }.padding(inset).frame(maxWidth: .infinity, alignment: .leading)
                        }
                }
            }
        }
    }

    private func branchView(_ branch: ArticlePracticeDocument.Branch, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(branch.label).font(BirdyDesign.heading)
            Text(branch.analysis).font(BirdyDesign.caption).foregroundStyle(.secondary).lineSpacing(4)
            if wide && !branch.evidence.isEmpty {
                HStack(alignment: .top, spacing: 28) {
                    paragraph(branch.main).frame(maxWidth: .infinity, alignment: .leading)
                    evidence(branch.evidence).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                paragraph(branch.main)
                if !branch.evidence.isEmpty { evidence(branch.evidence).padding(.leading, 16) }
            }
            Divider()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func evidence(_ items: [ArticlePracticeDocument.Paragraph]) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    paragraph(item)
                    if item.id != items.last?.id { Divider() }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func paragraph(_ item: ArticlePracticeDocument.Paragraph) -> some View {
        let isEnglish = english.contains(item.id)
        return Button {
            if isEnglish { english.remove(item.id) } else { english.insert(item.id) }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                if isEnglish {
                    BirdyExampleText(text: item.en, isReference: true)
                } else {
                    Text(item.zh).font(BirdyDesign.body).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("\(item.role) · 原文第 \(item.paragraph) 段")
                    .font(BirdyDesign.metadata).foregroundStyle(.secondary)
            }.foregroundStyle(.primary).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).id(item.id)
            .help(isEnglish ? "点击恢复中文" : "点击查看对应英文原段")
            .accessibilityLabel(isEnglish ? item.en : item.zh)
            .accessibilityValue("\(isEnglish ? "英文原段" : "中文译文")，原文第 \(item.paragraph) 段")
    }
}
