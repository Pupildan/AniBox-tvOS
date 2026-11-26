import SwiftUI

/// 手动选择弹幕：选源 → 搜番剧 → 选集 → 加载，并记住本剧的选择
struct DanmakuPickerView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) var dismiss
    @State private var src: DanmakuService.Source = DanmakuService.availableSources.first ?? .selfHosted
    @State private var q = ""
    @State private var animes: [JSON] = []
    @State private var anime: JSON?
    @State private var eps: [JSON] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("手动选择弹幕").font(.system(size: 44, weight: .bold))
            if DanmakuService.availableSources.isEmpty {
                Text("还没有配置弹幕源：请在「设置 → 弹幕」填写自建源地址或弹弹play AppId/AppSecret").foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                ForEach(DanmakuService.availableSources) { s in Chip(text: s.rawValue, selected: s == src) { src = s; Task { await search() } } }
                TextField("番剧名", text: $q).frame(width: 700).onSubmit { Task { await search() } }
                Button("搜索") { Task { await search() } }.buttonStyle(GlassButtonStyle(prominent: true))
            }
            .focusSection()
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if anime == nil {
                ScrollView { LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(animes, id: \.self) { a in
                        Button { Task { await pick(a) } } label: {
                            HStack { Text(a["animeTitle"].str).lineLimit(1); Spacer(); Text(a.first("typeDescription", "type").str).foregroundStyle(.secondary); Text("\(a["episodeCount"].int ?? 0) 集").foregroundStyle(.secondary) }
                                .frame(width: 1500)
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                } }
            } else {
                HStack {
                    Text(anime?["animeTitle"].str ?? "").font(.title3)
                    Button("返回番剧列表") { anime = nil; eps = [] }.buttonStyle(GlassButtonStyle())
                }
                .focusSection()
                ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.fixed(340), spacing: 24), count: 4), spacing: 24) {
                    ForEach(Array(eps.enumerated()), id: \.offset) { i, e in
                        Button { Task { await load(e, index: i) } } label: { Text(e["episodeTitle"].str).lineLimit(2).frame(width: 290, height: 80) }
                            .buttonStyle(GlassButtonStyle())
                    }
                } }
            }
        }
        .padding(70)
        .task { q = model.item.tvTitle.isEmpty ? model.item.title : model.item.tvTitle; await search() }
    }

    func search() async {
        busy = true; error = nil; anime = nil; defer { busy = false }
        do { animes = try await DanmakuService.search(src, q) } catch { self.error = error.localizedDescription; animes = [] }
    }
    func pick(_ a: JSON) async {
        busy = true; defer { busy = false }
        anime = a
        eps = (try? await DanmakuService.episodes(src, animeId: a.first("animeId", "bangumiId").str)) ?? []
    }
    func load(_ e: JSON, index: Int) async {
        busy = true; defer { busy = false }
        do {
            let list = try await DanmakuService.comments(src, episodeId: e["episodeId"].str)
            model.danmaku.load(list, label: "\(src.rawValue) · \(e["episodeTitle"].str)")
            model.toast = "已加载弹幕 \(list.count) 条"
            // 记住：本剧 → 番剧 id，集号偏移 = 所选索引 - (当前集号-1)
            let offset = index - max(0, model.item.episode - 1)
            DanmakuMemory.set(model.seriesKey, src: src.rawValue, animeId: anime?.first("animeId", "bangumiId").str ?? "", offset: offset)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
