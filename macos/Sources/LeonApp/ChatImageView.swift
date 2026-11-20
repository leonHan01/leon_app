import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ChatImageState: ObservableObject {
    @Published var image: NSImage?
    @Published var data: Data?
    @Published var failed = false
    @Published var retry = 0
    @Published var preview = false
}

struct ChatImageView: View {
    @ObservedObject var store: ChatStore
    let imageId: String
    var onQuote:(()->Void)? = nil
    var onFavorite:(()->Void)? = nil
    var onBranch:(()->Void)? = nil
    @StateObject private var loaded = ChatImageState()
    @State private var branchAfterPreview=false

    var body: some View {
        Button {
            if loaded.image != nil { loaded.preview = true } else { loaded.retry += 1 }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let image = loaded.image {
                    Image(nsImage: image).resizable().scaledToFit().padding(3)
                } else if loaded.failed {
                    Label("图片加载失败，点击重试", systemImage: "arrow.clockwise").font(.caption)
                } else { ProgressView().controlSize(.small) }
            }.frame(width: 240, height: 180).clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityLabel("聊天图片，点击查看大图")
            .contextMenu { saveButton;messageActions }
            .onDisappear { if !loaded.preview { loaded.image = nil; loaded.data = nil } }
            .task(id: "\(store.avatarSessionKey):\(imageId):\(loaded.retry):\(store.hasConnection)") {
                loaded.image = nil; loaded.data = nil; loaded.failed = false
                do {
                    let bytes = try await store.imageData(imageId)
                    guard !Task.isCancelled else { return }
                    loaded.image = NSImage(data: bytes); loaded.failed = loaded.image == nil
                    if loaded.image != nil { loaded.data = bytes }
                } catch { if !Task.isCancelled { loaded.failed = true } }
            }
            .onChange(of:store.searchConnectionID) {_ in branchAfterPreview=false}
            .sheet(isPresented: $loaded.preview,onDismiss:{if branchAfterPreview {branchAfterPreview=false;onBranch?()}}) {
                VStack(spacing: 12) {
                    HStack { Text("图片预览").font(.headline); Spacer(); Button("关闭") { loaded.preview = false }.keyboardShortcut(.cancelAction) }
                    ScrollView([.horizontal, .vertical]) {
                        if let image = loaded.image { Image(nsImage: image).textSelection(.disabled).contextMenu { saveButton;messageActions } }
                    }.background(Color(nsColor: .textBackgroundColor))
                        .overlay(alignment:.bottomTrailing) { downloadButton.padding(16) }
                }.padding(20).frame(width: 820, height: 620)
            }
    }
    @ViewBuilder private var messageActions:some View {
        if let onQuote {Button("引用") {loaded.preview=false;onQuote()}}
        if let onFavorite {Button("收藏") {loaded.preview=false;onFavorite()}}
        if let onBranch {Button("从这里创建分支") {if loaded.preview {branchAfterPreview=true;loaded.preview=false} else {onBranch()}}}
    }
    private var saveButton: some View {
        Button { saveImage() } label: { Label("保存图片…",systemImage:"square.and.arrow.down") }.disabled(loaded.data == nil)
    }
    private var downloadButton: some View {
        Button { saveImage() } label: {
            Image(systemName:"arrow.down.to.line").font(.system(size:20,weight:.medium))
                .foregroundStyle(.primary).frame(width:48,height:48)
                .background(.regularMaterial,in:Circle())
                .overlay(Circle().stroke(.primary.opacity(0.08),lineWidth:1))
                .shadow(color:.black.opacity(0.15),radius:7,y:3)
        }
        .buttonStyle(.plain).disabled(loaded.data == nil).help("下载并保存图片")
        .accessibilityLabel("下载并保存图片").accessibilityIdentifier("download_chat_image")
    }
    private func saveImage() {
        guard let data = loaded.data else {return}
        let panel = NSSavePanel();panel.title = "保存图片";panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = "Leon-\(imageId).jpg";panel.canCreateDirectories = true
        let completion: (NSApplication.ModalResponse) -> Void = { result in
            guard result == .OK, let url = panel.url else {return}
            do {try data.write(to:url,options:.atomic)}
            catch {
                let alert = NSAlert(error:error)
                if let window = NSApp.keyWindow {alert.beginSheetModal(for:window)} else {alert.runModal()}
            }
        }
        if let window = NSApp.keyWindow {panel.beginSheetModal(for:window,completionHandler:completion)} else {panel.begin(completionHandler:completion)}
    }
}
