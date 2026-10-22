import SwiftUI

/// Shared structure for browsing collections; keeps filters next to their results.
struct BirdyCategorySidebar: View {
    var title = "话题"
    let categories: [String]
    @Binding var selection: String
    let count: (String) -> Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(BirdyDesign.heading)
                .padding(.horizontal, 22).padding(.vertical, 18)
            Divider()
            ScrollView {
                VStack(spacing: 4) {
                    categoryRow("全部", label: title == "话题" ? "全部话题" : "全部句式")
                    ForEach(categories, id: \.self) { categoryRow($0, label: $0) }
                }.padding(12)
            }
        }.background(BirdyDesign.quietSurface)
    }

    private func categoryRow(_ value: String, label: String) -> some View {
        Button { selection = value } label: {
            HStack(spacing: 8) {
                Text(label).font(BirdyDesign.body)
                Spacer(minLength: 4)
                Text("\(count(value))").font(BirdyDesign.metadata).monospacedDigit()
                    .foregroundStyle(.secondary)
            }.foregroundStyle(.primary).padding(.horizontal, 10).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selection == value ? BirdyDesign.tint : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(label)，\(count(value)) 条")
            .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

struct BirdyLibrarySearch: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button { focused = true } label: {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            }.buttonStyle(.plain).accessibilityLabel(placeholder)
            TextField(placeholder, text: $text).textFieldStyle(.plain).focused($focused)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = ""; focused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("清空搜索").accessibilityLabel("清空搜索")
            }
        }.padding(.horizontal, 10).padding(.vertical, 7)
            .background(BirdyDesign.quietSurface, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct BirdyLibraryTitle: View {
    let title: String
    let count: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(BirdyDesign.section)
            Text(count).font(BirdyDesign.metadata).foregroundStyle(.secondary).monospacedDigit()
        }.fixedSize(horizontal: true, vertical: false)
    }
}
