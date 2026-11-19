import Foundation

/// Foundation parses Markdown; these blocks preserve its structure for native SwiftUI layout.
struct MessageMarkdown {
    struct Block: Identifiable {
        enum Kind {
            case text, heading(Int), code(String?), rule, table
        }
        let id: Int
        var kind: Kind
        var text: AttributedString
        var indentation = 0
        var marker: String?
        var quoteDepth = 0
        var columns: [PresentationIntent.TableColumn] = []
        var rows: [[AttributedString]] = []
    }

    let blocks: [Block]

    init(_ source: String) {
        guard let parsed = try? AttributedString(markdown: source, options: .init(
            allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible
        )), !parsed.characters.isEmpty else {
            blocks = [Block(id: 0, kind: .text, text: AttributedString(source))]
            return
        }
        var result: [Block] = []
        var seenItems = Set<Int>()
        for (intent, range) in parsed.runs[\.presentationIntent] {
            let components = intent?.components ?? []
            let text = Self.inlineText(AttributedString(parsed[range]))
            if let table = components.first(where: { if case .table = $0.kind { return true }; return false }),
               case .table(let columns) = table.kind {
                if result.last?.id != table.identity {
                    var block = Block(id: table.identity, kind: .table, text: AttributedString())
                    block.columns = columns
                    Self.decorate(&block, components: components, seenItems: &seenItems)
                    result.append(block)
                }
                let row = components.compactMap { component -> Int? in
                    switch component.kind {
                    case .tableHeaderRow: return 0
                    case .tableRow(let index): return index
                    default: return nil
                    }
                }.first ?? 0
                let column = components.compactMap { component -> Int? in
                    if case .tableCell(let index) = component.kind { return index }; return nil
                }.first ?? 0
                let index = result.count - 1
                while result[index].rows.count <= row {
                    result[index].rows.append(Array(repeating: AttributedString(), count: columns.count))
                }
                if column < columns.count { result[index].rows[row][column] += text }
                continue
            }
            var block = Block(id: components.first?.identity ?? -result.count - 1, kind: .text, text: text)
            switch components.first?.kind {
            case .header(let level): block.kind = .heading(level)
            case .codeBlock(let language): block.kind = .code(language)
            case .thematicBreak: block.kind = .rule
            default: break
            }
            Self.decorate(&block, components: components, seenItems: &seenItems)
            result.append(block)
        }
        blocks = result
    }

    private static func decorate(_ block: inout Block, components: [PresentationIntent.IntentType], seenItems: inout Set<Int>) {
        let items = components.filter { if case .listItem = $0.kind { return true }; return false }
        block.indentation = max(0, items.count - 1) * 20
        block.quoteDepth = components.filter { $0.kind == .blockQuote }.count
        if let item = items.first, case .listItem(let ordinal) = item.kind {
            if seenItems.insert(item.identity).inserted {
                let list = components.first { $0.kind == .orderedList || $0.kind == .unorderedList }
                block.marker = list?.kind == .orderedList ? "\(ordinal)." : "•"
            } else {
                block.indentation += 24
            }
        }
    }

    private static func inlineText(_ source: AttributedString) -> AttributedString {
        var result = AttributedString()
        for run in source.runs {
            var part = AttributedString(source[run.range])
            // Chat messages keep ordinary line breaks, including inside lists and quotes.
            if run.inlinePresentationIntent?.contains(.softBreak) == true { part = AttributedString("\n") }
            part.presentationIntent = nil
            if let url = part.link, !isAllowedLink(url) { part.link = nil }
            // Images display their alt text, without fetching remote resources.
            part.imageURL = nil
            result += part
        }
        return result
    }

    static func isAllowedLink(_ url: URL) -> Bool {
        ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }
}
