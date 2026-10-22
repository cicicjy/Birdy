import SwiftUI

/// A local, source-backed graph. Only the selected word expands; the vocabulary list stays in place.
struct ExpressionGraphView: View {
    @ObservedObject var store: AppStore
    let word: VocabularyItem
    let openRecord: (UUID) -> Void
    @State private var focus: ExpressionEvidence?
    @State private var selectedLinkID: String?
    @State private var page = 0
    private var center: ExpressionEvidence? { focus ?? store.expressionEvidence(for: word) }
    private var links: [ExpressionLink] { center.map { store.links(for: $0) } ?? [] }
    private var selected: ExpressionLink? { links.first { $0.id == selectedLinkID } ?? links.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("原文表达关联").font(BirdyDesign.section)
                Spacer()
                if focus != nil {
                    Button("回到收藏词") { focus = nil; page = 0; selectedLinkID = nil }
                        .font(BirdyDesign.caption)
                }
            }
            if let center, !links.isEmpty {
                graph(center: center)
                if let selected {
                    evidencePanel(selected, center: center)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.refreshingExpressionLinks ? "正在从摘录中寻找不同说法…" : "还没有找到有依据的近义表达")
                        .font(BirdyDesign.emphasis)
                    Text(center == nil ? "这个词条无法在关联的摘录中逐字定位。可先核对词条或回到精读记录查看原文。" : "只查找同一篇文章或同一来源中实际出现的表达；简单指代不会展示。没有合适表达时会保持为空。")
                        .font(BirdyDesign.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if store.refreshingExpressionLinks {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("重新识别原文表达") { Task { await store.refreshExpressionLinks(force: true) } }
                    }
                }.padding(.vertical, 16)
            }
        }
        .padding(20)
        .background(BirdyDesign.quietSurface, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: word.id) { _, _ in focus = nil; page = 0; selectedLinkID = nil }
    }

    private func graph(center: ExpressionEvidence) -> some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let compact = geometry.size.width < 640
                let pageSize = 4
                let pageCount = max(1, (links.count + pageSize - 1) / pageSize)
                let safePage = min(page, pageCount - 1)
                let shown = Array(links.dropFirst(safePage * pageSize).prefix(pageSize))
                let origin = CGPoint(x: geometry.size.width / 2, y: 215)
                ZStack {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, link in
                        let point = satellite(index, count: shown.count, width: geometry.size.width, compact: compact)
                        Path { path in path.move(to: origin); path.addLine(to: point) }
                            .stroke(selected?.id == link.id ? BirdyDesign.accent.opacity(0.7) : Color.secondary.opacity(0.3), lineWidth: selected?.id == link.id ? 1.5 : 1)
                            .accessibilityHidden(true)
                        Button { selectedLinkID = link.id } label: {
                            VStack(spacing: 5) {
                                Text(link.other(than: center).phrase).font(BirdyDesign.example)
                                    .foregroundStyle(.primary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                Text(link.label).font(BirdyDesign.metadata).foregroundStyle(.secondary)
                            }.padding(10).frame(width: compact ? 130 : 150).frame(minHeight: 64)
                                .background(BirdyDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected?.id == link.id ? BirdyDesign.accent : Color.secondary.opacity(0.4), lineWidth: 1))
                        }.buttonStyle(.plain).position(point)
                            .accessibilityLabel("\(link.other(than: center).phrase)，\(link.label)，查看原句与区别")
                    }
                    Text(center.phrase).font(BirdyDesign.word).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).padding(14).frame(width: 170).frame(minHeight: 70)
                        .background(BirdyDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(BirdyDesign.accent, lineWidth: 2))
                        .position(origin)
                }
            }.frame(height: 430)
            HStack {
                Text("\(links.count) 个关联 · 点击周围表达查看区别").font(BirdyDesign.caption).foregroundStyle(.secondary)
                Spacer()
                if links.count > 4 {
                    Button("上一组") { page = max(0, page - 1) }.disabled(page == 0)
                    Button("下一组") { page += 1 }.disabled((page + 1) * 4 >= links.count)
                }
            }
        }
    }
    private func satellite(_ index: Int, count: Int, width: CGFloat, compact: Bool) -> CGPoint {
        let positions: [(CGFloat, CGFloat)] = [(0.22, 70), (0.78, 70), (0.22, 360), (0.78, 360)]
        return CGPoint(x: width * positions[index].0, y: positions[index].1)
    }

    private func evidencePanel(_ link: ExpressionLink, center: ExpressionEvidence) -> some View {
        let other = link.other(than: center)
        return VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack(alignment: .top) {
                Text(link.label).font(BirdyDesign.heading)
                Spacer()
                Button("隐藏这条关联") { store.dismissExpressionLink(link) }.font(BirdyDesign.caption)
            }
            Text(link.distinction).font(BirdyDesign.body).lineSpacing(4).textSelection(.enabled)
            evidenceRow(center)
            evidenceRow(other)
            HStack {
                Button("以「\(other.phrase)」为中心") { focus = other; page = 0; selectedLinkID = nil }
                Spacer()
                Text("模型识别 · 原句已核对").font(BirdyDesign.metadata).foregroundStyle(.secondary)
            }
        }
    }
    private func evidenceRow(_ evidence: ExpressionEvidence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(evidence.phrase).font(BirdyDesign.emphasis)
            BirdyExampleText(text: evidence.quote).textSelection(.enabled)
            HStack {
                Button("回到精读记录") { openRecord(evidence.recordID) }.buttonStyle(.plain)
                if let record = store.records.first(where: { $0.id == evidence.recordID }),
                   let source = record.sourceURL,
                   let url = CaptureService.chromeTextURL(sourceURL: source, quote: evidence.phrase) {
                    Link("打开原文", destination: url)
                }
            }.font(BirdyDesign.caption)
        }
    }
}
