import SwiftUI
import AppKit

@MainActor
final class MentionEditorState: ObservableObject {
    @Published var visible = false
    @Published var candidates: [AgentInfo] = []
    @Published var selectedIndex = 0
    weak var editor: NSTextView?
    var eligible: [AgentInfo] = []
    var group = false
    var conversationId = ""
    private var currentKey = ""
    private var dismissedKey = ""
    private var candidateKey = ""

    func refresh() {
        guard group, let editor, editor.window?.firstResponder === editor, !editor.hasMarkedText(),
              let token = MentionCompletion.token(in: editor.string, selection: editor.selectedRange()) else {
            hide(); dismissedKey = ""; currentKey = ""; return
        }
        let key = "\(conversationId):\(token.range):\(editor.selectedRange().location):\(token.query)"
        guard key != dismissedKey else { hide(); return }
        let matching = Array(eligible.filter { MentionCompletion.matches(name: $0.name, handle: $0.handle, query: token.query) }.prefix(8))
        if key != currentKey { selectedIndex = 0 }
        currentKey = key
        let signature = matching.map { "\($0.id):\($0.name):\($0.handle):\($0.avatarId ?? "")" }.joined(separator: "|")
        if signature != candidateKey { candidateKey = signature; candidates = matching }
        if selectedIndex >= candidates.count, selectedIndex != 0 { selectedIndex = 0 }
        if !visible { visible = true }
    }
    func hide(dismiss: Bool = false) {
        if dismiss { dismissedKey = currentKey }
        if visible { visible = false }
    }
    func choose(_ index: Int) {
        guard candidates.indices.contains(index), let editor, !editor.hasMarkedText(),
              let token = MentionCompletion.token(in: editor.string, selection: editor.selectedRange()),
              eligible.contains(where: { $0.id == candidates[index].id }),
              MentionCompletion.matches(name: candidates[index].name, handle: candidates[index].handle, query: token.query) else { return }
        let selected = candidates[index]
        let result = MentionCompletion.replacing(token, in: editor.string, with: selected.handle)
        editor.window?.makeFirstResponder(editor)
        editor.insertText(result.insertion, replacementRange: token.range)
        editor.setSelectedRange(NSRange(location: result.caret, length: 0))
        hide(); currentKey = ""; dismissedKey = ""
    }
    func command(_ selector: Selector) -> Bool {
        guard let editor, !editor.hasMarkedText() else { return false }
        refresh()
        guard visible else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) { hide(dismiss: true); return true }
        guard !candidates.isEmpty else { return false }
        if selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.moveUp(_:)) {
            let delta = selector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            selectedIndex = (selectedIndex + delta + candidates.count) % candidates.count; return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertTab(_:)) {
            choose(selectedIndex); return true
        }
        return false
    }
}

private final class ComposerTextView: NSTextView {
    var send: (() -> Void)?
    var focusChanged: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), event.modifierFlags.contains(.command), [36, 76].contains(event.keyCode) { send?(); return }
        super.keyDown(with: event)
    }
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); focusChanged?(); return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); focusChanged?(); return result }
    override func unmarkText() { super.unmarkText(); focusChanged?() }
}

private struct NativeMentionEditor: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var state: MentionEditorState
    let agents: [AgentInfo]
    let group: Bool
    let conversationId: String
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let editor = ComposerTextView(frame: .zero)
        editor.isRichText = false; editor.allowsUndo = true; editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14); editor.textColor = .textColor
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.minSize = NSSize(width: 0, height: 82)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 82)
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = .width; editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.setAccessibilityLabel("消息")
        editor.string = text; editor.delegate = context.coordinator
        scroll.documentView = editor; state.editor = editor
        let coordinator = context.coordinator
        editor.focusChanged = { [weak coordinator] in coordinator?.scheduleRefresh() }
        editor.send = { [weak coordinator] in coordinator?.parent.onSend() }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text, !editor.hasMarkedText() {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        state.editor = editor; state.eligible = agents; state.group = group; state.conversationId = conversationId
        context.coordinator.scheduleRefresh()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMentionEditor
        private var refreshQueued = false
        init(_ parent: NativeMentionEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string; scheduleRefresh()
        }
        func textViewDidChangeSelection(_ notification: Notification) { scheduleRefresh() }
        func textDidEndEditing(_ notification: Notification) { parent.state.hide() }
        func scheduleRefresh() {
            guard !refreshQueued else { return }; refreshQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.refreshQueued = false; self.parent.state.refresh()
            }
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if NSApp.currentEvent?.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty == false { return false }
            return parent.state.command(commandSelector)
        }
    }
}

struct MentionComposer: View {
    @ObservedObject var store: ChatStore
    @StateObject private var state = MentionEditorState()
    var body: some View {
        VStack(spacing: 8) {
            if state.visible {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("提及 Agent").font(.caption.bold())
                        Spacer()
                        Text("↑↓ 选择 · Enter/Tab 确认 · Esc 关闭").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 9).padding(.top, 5)
                    if state.candidates.isEmpty { Text("没有匹配的 Agent").font(.caption).foregroundStyle(.secondary).padding(10) }
                    else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 2) {
                                    ForEach(state.candidates.indices, id: \.self) { index in
                                        let agent = state.candidates[index]
                                        Button { state.choose(index) } label: {
                                            HStack(spacing: 10) {
                                                AgentAvatarView(store: store, avatarId: agent.avatarId ?? "alfred", size: 30)
                                                Text(agent.name).font(.callout)
                                                Text("@\(agent.handle)").font(.caption).foregroundStyle(.secondary)
                                                Spacer()
                                            }.padding(7).background(index == state.selectedIndex ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                        }.buttonStyle(.plain).id(index)
                                    }
                                }
                            }.frame(height: min(CGFloat(state.candidates.count) * 46, 184))
                                .onChange(of: state.selectedIndex) { proxy.scrollTo($0, anchor: .center) }
                        }
                    }
                }.padding(6).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            NativeMentionEditor(text: $store.draft, state: state, agents: store.availableAgents,
                group: store.selectedConversation?.kind == "group", conversationId: store.selectedConversationId,
                onSend: { Task { await store.sendDraft() } })
                .frame(height: 82).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.15)))
        }
    }
}
