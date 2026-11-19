import SwiftUI
import AppKit

struct MarkdownMessageView: View, Equatable {
    let source: String
    let mine: Bool

    init(_ source: String, mine: Bool) {
        self.source = source
        self.mine = mine
    }

    var body: some View {
        let document = MessageMarkdown(source)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(document.blocks) { block in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<block.quoteDepth, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2).fill(foreground.opacity(0.35)).frame(width: 3)
                    }
                    if let marker = block.marker {
                        Text(marker).font(.system(size: 14)).frame(minWidth: 16, alignment: .trailing)
                    }
                    content(block)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, CGFloat(block.indentation))
            }
        }
        .foregroundStyle(foreground)
        .tint(mine ? .white : .accentColor)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            MessageMarkdown.isAllowedLink(url) ? .systemAction : .discarded
        })
        .contextMenu {
            Button("复制原文") { copy(source) }
        }
    }

    private var foreground: Color { mine ? .white : .primary }
    private var insetBackground: Color { mine ? .black.opacity(0.13) : .primary.opacity(0.055) }

    @ViewBuilder
    private func content(_ block: MessageMarkdown.Block) -> some View {
        switch block.kind {
        case .rule:
            Rectangle().fill(foreground.opacity(0.25)).frame(height: 1).padding(.vertical, 5)
        case .code(let language):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(language ?? "代码").font(.system(size: 10, weight: .medium))
                    Spacer()
                    Button { copy(String(block.text.characters)) } label: {
                        Image(systemName: "doc.on.doc")
                    }.buttonStyle(.borderless).help("复制代码").accessibilityLabel("复制代码")
                }.foregroundStyle(foreground.opacity(0.75))
                ScrollView(.horizontal) {
                    Text(String(block.text.characters)).font(.system(size: 13, design: .monospaced))
                        .lineSpacing(4).fixedSize(horizontal: true, vertical: true)
                        .padding(.bottom, 4)
                }
            }.padding(10).background(insetBackground, in: RoundedRectangle(cornerRadius: 8))
        case .table:
            ScrollView(.horizontal) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(block.rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(block.columns.indices, id: \.self) { column in
                                Text(styled(block.rows[row][column], size: 13, bold: row == 0))
                                    .lineSpacing(3).padding(.horizontal, 10).padding(.vertical, 8)
                                    .frame(minWidth: 70, maxWidth: 240, alignment: alignment(block.columns[column].alignment))
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .background(row == 0 ? insetBackground : .clear)
                                    .overlay(Rectangle().stroke(foreground.opacity(0.18), lineWidth: 0.5))
                            }
                        }
                    }
                }.padding(1)
            }
        case .heading(let level):
            Text(styled(block.text, size: [23.0, 20, 17, 15, 14, 14][min(max(level, 1), 6) - 1], bold: true))
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        case .text:
            Text(styled(block.text)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func styled(_ source: AttributedString, size: CGFloat = 14, bold: Bool = false) -> AttributedString {
        var value = source
        for run in source.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = Font.system(size: size, design: intent.contains(.code) ? .monospaced : .default)
            if bold || intent.contains(.stronglyEmphasized) { font = font.bold() }
            if intent.contains(.emphasized) { font = font.italic() }
            value[run.range].font = font
            if intent.contains(.strikethrough) { value[run.range].strikethroughStyle = .single }
            if intent.contains(.code) { value[run.range].backgroundColor = insetBackground }
            if run.link != nil {
                value[run.range].foregroundColor = mine ? .white : .accentColor
                value[run.range].underlineStyle = .single
            }
        }
        return value
    }

    private func alignment(_ value: PresentationIntent.TableColumn.Alignment) -> Alignment {
        switch value {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        @unknown default: return .leading
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
