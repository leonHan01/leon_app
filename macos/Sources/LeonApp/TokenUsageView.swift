import SwiftUI

struct TokenUsageView: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    private func total(_ field: KeyPath<ModelUsage, Int64>) -> Int64 {
        store.modelUsage.reduce(0) { $0 + $1[keyPath: field] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Token 用量").font(.title2.bold())
            Text("当前服务累计用量，按服务商与模型汇总，包含所有会话、工作流、上下文压缩和归档总结调用。")
                .font(.callout).foregroundStyle(.secondary)
            if store.usageBusy { ProgressView("正在读取用量…").controlSize(.small) }
            if let error = store.usageError { Text(error).foregroundStyle(.red) }
            if let updated = store.usageLoadedAt {
                HStack(spacing: 28) {
                    metric("总 Token", total(\.totalTokens))
                    metric("输入", total(\.inputTokens))
                    metric("输出", total(\.outputTokens))
                }
                Text("已报告用量 \(total(\.reportedCalls).formatted()) 次 · 未报告用量 \(total(\.unreportedCalls).formatted()) 次")
                    .font(.caption).foregroundStyle(.secondary)
                if store.modelUsage.isEmpty {
                    Text("暂无用量记录").frame(maxWidth: .infinity, minHeight: 110).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(store.modelUsage) { row in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(row.provider + " · " + row.model).font(.headline).textSelection(.enabled)
                                    Text("总计 \(row.totalTokens.formatted()) · 输入 \(row.inputTokens.formatted()) · 输出 \(row.outputTokens.formatted()) Token")
                                        .font(.callout).textSelection(.enabled)
                                    Text("已报告 \(row.reportedCalls.formatted()) 次 · 未报告 \(row.unreportedCalls.formatted()) 次")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 280)
                }
                Text("读取于 " + updated.formatted(date: .abbreviated, time: .standard))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("仅累计开始记录以来模型实际返回的用量；未报告的调用不计入 Token 总数。缓存与推理 Token 已包含在模型返回的总量中。此处为全局累计，不代表当前会话消耗或账单金额。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("刷新") { Task { await store.loadUsage() } }.disabled(store.usageBusy)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 560)
        .task { await store.loadUsage() }
    }
    private func metric(_ title: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted()).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}
