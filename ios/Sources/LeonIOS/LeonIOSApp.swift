import SwiftUI

@main
struct LeonIOSApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var store: ChatStore?
    @State private var failure: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let store { NativeRootView(store:store) }
                else if let failure { ContentUnavailableFallback(message:failure) }
                else { ProgressView("正在读取本地登录…") }
            }
            .task {
                guard store == nil else { return }
                do {
                    let value = ChatStore(disk:try FilePersistence.application(),credentials:KeychainCredentials())
                    await value.initialize(); store = value; value.setActive(phase == .active)
                } catch { failure = error.localizedDescription }
            }
            .onChange(of:phase) { store?.setActive($0 == .active) }
        }
    }
}
struct ContentUnavailableFallback: View {
    let message: String
    var body: some View { VStack(spacing:14) { Image(systemName:"exclamationmark.triangle").font(.largeTitle); Text(message); Text("请检查设备存储后重新打开应用。").font(.caption).foregroundStyle(.secondary) }.padding() }
}
