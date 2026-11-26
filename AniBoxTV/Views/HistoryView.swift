import SwiftUI

/// 观影记录：时间线 + 观看热力图 + 年度报告入口（对应原项目 WatchHistoryView / WatchReport）
struct HistoryView: View {
    @ObservedObject var store = HistoryStore.shared
    @State private var server: [MediaItem] = []
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    HStack {
                        Text("观影记录").font(.system(size: 56, weight: .heavy))
                        Spacer()
                        NavigationLink(value: Route.report) { Label("年度报告", systemImage: "chart.bar.xaxis") }.buttonStyle(GlassButtonStyle(prominent: true))
                        Button(role: .destructive) { store.clear() } label: { Label("清空本地记录", systemImage: "trash") }.buttonStyle(GlassButtonStyle())
                    }
                    .focusSection()
                    Heatmap(data: store.dailySeconds()).padding(30).glass(30).focusable()
                    if !server.isEmpty {
                        ShelfRow(title: "飞牛「继续观看」") {
                            ForEach(server) { i in NavigationLink(value: OpenItem.route(i)) { PosterCardLabel(item: i) }.buttonStyle(CardButtonStyle()) }
                        }
                        .padding(.horizontal, -80)
                    }
                    Text("本机记录").font(.system(size: 34, weight: .bold))
                    LazyVStack(spacing: 20) {
                        ForEach(store.entries) { e in
                            NavigationLink(value: Route.detail(MediaItem(raw: .object(["guid": .string(e.seriesGuid ?? e.guid), "title": .string(e.title), "type": .string(e.seriesGuid == nil ? e.type : "TV")])))) {
                                HStack(spacing: 30) {
                                    RemoteImage(url: FnClient.shared.imageURL(e.poster, width: 300)).aspectRatio(contentMode: .fill).frame(width: 120, height: 180).clipShape(RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(e.title).font(.system(size: 30, weight: .bold))
                                        Text(e.subtitle).foregroundStyle(.secondary)
                                        ProgressView(value: min(1, e.progress)).frame(width: 600)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 8) {
                                        Text(e.lastWatched, style: .date)
                                        Text(String(format: "累计 %.1f 小时", e.watchedSeconds / 3600)).foregroundStyle(.secondary)
                                        if e.finished { Label("看完", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                                    }
                                }
                                .padding(26).glass(26)
                            }
                            .buttonStyle(CardButtonStyle())
                            .contextMenu { Button("删除此记录", role: .destructive) { store.remove(e.guid) } }
                        }
                    }
                }
                .padding(80)
            }
        }
        .task { server = MediaItem.list((try? await FnClient.shared.continueWatching()) ?? []) }
    }
}

struct Heatmap: View {
    let data: [(Date, Double)]
    var body: some View {
        let weeks = stride(from: 0, to: data.count, by: 7).map { Array(data[$0..<min($0 + 7, data.count)]) }
        let maxV = max(1, data.map { $0.1 }.max() ?? 1)
        VStack(alignment: .leading, spacing: 14) {
            Text("近半年观看热力图").font(.system(size: 28, weight: .bold))
            HStack(spacing: 6) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, w in
                    VStack(spacing: 6) {
                        ForEach(Array(w.enumerated()), id: \.offset) { _, d in
                            RoundedRectangle(cornerRadius: 4).fill(d.1 == 0 ? Color.white.opacity(0.07) : Color.green.opacity(0.25 + 0.75 * d.1 / maxV))
                                .frame(width: 22, height: 22)
                        }
                    }
                }
            }
            Text(String(format: "合计 %.1f 小时", data.reduce(0) { $0 + $1.1 } / 3600)).foregroundStyle(.secondary)
        }
    }
}

struct WatchReportView: View {
    @ObservedObject var store = HistoryStore.shared
    @State private var year = Calendar.current.component(.year, from: Date())
    var body: some View {
        let r = store.report(year: year)
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    HStack(spacing: 20) {
                        Text("\(String(year)) 年度观影报告").font(.system(size: 60, weight: .heavy))
                        Chip(text: "上一年") { year -= 1 }
                        Chip(text: "下一年") { year += 1 }
                    }
                    .focusSection()
                    HStack(spacing: 30) {
                        big(String(format: "%.0f", r.totalHours), "小时")
                        big("\(r.titles)", "部作品")
                        big("\(r.finished)", "部看完")
                        if let b = r.busiestDay { big(String(format: "%.1f", b.1 / 3600), "小时 · 最长一天") }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("月度分布").font(.system(size: 30, weight: .bold))
                        HStack(alignment: .bottom, spacing: 20) {
                            let mx = max(1, r.byMonth.max() ?? 1)
                            ForEach(0..<12, id: \.self) { i in
                                VStack {
                                    RoundedRectangle(cornerRadius: 8).fill(.cyan.gradient).frame(width: 60, height: max(4, 260 * r.byMonth[i] / mx))
                                    Text("\(i + 1)月").font(.caption)
                                }
                            }
                        }
                    }
                    .padding(36).glass(30).focusable()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("看得最多").font(.system(size: 30, weight: .bold))
                        ForEach(Array(r.topTitles.enumerated()), id: \.offset) { i, t in
                            HStack { Text("\(i + 1). \(t.0)"); Spacer(); Text(String(format: "%.1f 小时", t.1)).foregroundStyle(.secondary) }.font(.system(size: 26))
                        }
                    }
                    .padding(36).glass(30).focusable()
                }
                .padding(80)
            }
        }
    }
    func big(_ v: String, _ t: String) -> some View {
        VStack(spacing: 6) { Text(v).font(.system(size: 70, weight: .heavy)); Text(t).foregroundStyle(.secondary) }
            .frame(width: 360, height: 200).glass(30)
    }
}
