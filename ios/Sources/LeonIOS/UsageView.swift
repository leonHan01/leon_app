import SwiftUI

@MainActor
struct UsageView: View {
    @ObservedObject var store: ChatStore
    var close: () -> Void
    private var totals: (input:Int64,output:Int64,total:Int64,reported:Int64,unreported:Int64) {
        store.usage.reduce((0,0,0,0,0)) {($0.0+$1.inputTokens,$0.1+$1.outputTokens,$0.2+$1.totalTokens,$0.3+$1.reportedCalls,$0.4+$1.unreportedCalls)}
    }
    var body: some View {
        MobileDialog(title:"Token 用量",close:close) {
            VStack(alignment:.leading,spacing:0) {
                Text("当前用户触发的 Agent 回复、上下文压缩与归档用量。群聊用量计入发起者。").font(.system(size:13)).foregroundStyle(MobileStyle.muted)
                if !store.loggedIn {Text("请先在设置中连接服务").font(.system(size:14)).padding(.top,12)}
                if store.loadingUsage {Text("正在读取用量…").font(.system(size:14)).padding(.top,12)}
                if let error = store.usageError {Text(error).font(.system(size:14)).foregroundStyle(MobileStyle.color(0xB3261E)).padding(.top,12)}
                if let date = store.usageLoadedAt {usageRows(date)}
                Text("按 2026-11-19 官网公开文本价格估算：输入分别按全部缓存命中 / 全部未命中计算；DeepSeek 分别使用非高峰 / 高峰价格。历史缓存命中、计费时段、价格变动和未报告调用无法还原，金额不是账单；可能不含长上下文、工具及其他费用。").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.top,16)
                Link("OpenAI：https://developers.openai.com/api/docs/pricing",destination:URL(string:"https://developers.openai.com/api/docs/pricing")!).font(.system(size:12)).padding(.top,12)
                Link("DeepSeek：https://api-docs.deepseek.com/quick_start/pricing/",destination:URL(string:"https://api-docs.deepseek.com/quick_start/pricing/")!).font(.system(size:12)).padding(.top,6).padding(.bottom,8)
            }
        } actions:{
            MobileTextButton(title:"刷新") {Task {await store.loadUsage()}}.disabled(!store.loggedIn || store.loadingUsage || store.configuring)
            MobileTextButton(title:"关闭",action:close)
        }.task {await store.loadUsage()}
    }
    private func usageRows(_ date: Date) -> some View {
        VStack(alignment:.leading,spacing:0) {
            Text("总 Token  \(number(totals.total))").font(.system(size:22,weight:.bold)).padding(.top,18).padding(.bottom,8)
            Text("输入 \(number(totals.input)) · 输出 \(number(totals.output))").font(.system(size:14))
            Text("已报告用量 \(number(totals.reported)) 次 · 未报告用量 \(number(totals.unreported)) 次").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.top,4)
            let costs = store.usage.compactMap {UsagePricing.estimate($0)}
            if !costs.isEmpty {Text("已匹配模型估算  \(UsagePricing.label(.init(low:costs.reduce(0){$0+$1.low},high:costs.reduce(0){$0+$1.high}))) USD").font(.system(size:15,weight:.bold)).padding(.top,12).padding(.bottom,4)}
            if costs.count<store.usage.count {Text("部分模型暂无可匹配价格，未计入以上金额。").font(.system(size:12)).foregroundStyle(MobileStyle.muted)}
            if store.usage.isEmpty {Text("暂无用量记录").font(.system(size:14)).padding(.top,8)}
            ForEach(store.usage) {row in
                Text("\(row.provider) · \(row.model)").font(.system(size:15,weight:.bold)).padding(.top,20).padding(.bottom,6)
                Text("总计 \(number(row.totalTokens)) Token\n输入 \(number(row.inputTokens)) · 输出 \(number(row.outputTokens))").font(.system(size:14)).textSelection(.enabled)
                Text("已报告 \(number(row.reportedCalls)) 次 · 未报告 \(number(row.unreportedCalls)) 次").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.top,4)
                Text(UsagePricing.estimate(row).map {"估算 \(UsagePricing.label($0)) USD"} ?? "暂无可匹配价格").font(.system(size:14)).padding(.top,4)
            }
            Text("读取于 \(date.formatted())").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.top,18)
        }
    }
    private func number(_ value: Int64) -> String {value.formatted(.number)}
}
