import SwiftUI
import AppKit

@MainActor
final class ChatImageState: ObservableObject {
    @Published var image: NSImage?
    @Published var failed = false
    @Published var retry = 0
    @Published var preview = false
}

struct ChatImageView: View {
    @ObservedObject var store: ChatStore
    let imageId: String
    @StateObject private var loaded = ChatImageState()

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
            .onDisappear { if !loaded.preview { loaded.image = nil } }
            .task(id: "\(store.avatarSessionKey):\(imageId):\(loaded.retry):\(store.hasConnection)") {
                loaded.image = nil; loaded.failed = false
                do {
                    let bytes = try await store.imageData(imageId)
                    guard !Task.isCancelled else { return }
                    loaded.image = NSImage(data: bytes); loaded.failed = loaded.image == nil
                } catch { if !Task.isCancelled { loaded.failed = true } }
            }
            .sheet(isPresented: $loaded.preview) {
                VStack(spacing: 12) {
                    HStack { Text("图片预览").font(.headline); Spacer(); Button("关闭") { loaded.preview = false }.keyboardShortcut(.cancelAction) }
                    ScrollView([.horizontal, .vertical]) {
                        if let image = loaded.image { Image(nsImage: image).textSelection(.disabled) }
                    }.background(Color(nsColor: .textBackgroundColor))
                }.padding(20).frame(width: 820, height: 620)
            }
    }
}
