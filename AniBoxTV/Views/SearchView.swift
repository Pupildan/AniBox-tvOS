import SwiftUI

struct SearchView: View {
    @State private var q = ""
    @State private var results: [MediaItem] = []
    @State private var bgm: [JSON] = []
    @State private var busy = false
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    if !results.isEmpty {
                        ShelfRow(title: "飞牛影视", trailing: "\(results.count) 个结果") {
                            ForEach(results) { i in NavigationLink(value: OpenItem.route(i)) { PosterCardLabel(item: i) }.buttonStyle(CardButtonStyle()) }
                        }
                    }
                    if !bgm.isEmpty {
                        ShelfRow(title: "Bangumi") {
                            ForEach(bgm, id: \.self) { b in BgmCard(s: b) }
                        }
                    }
                    if !busy && results.isEmpty && !q.isEmpty { Text("没有找到「\(q)」").foregroundStyle(.secondary).padding(80) }
                }
            }
        }
        .searchable(text: $q, prompt: "搜索影片、剧集、动画")
        .task(id: q) {
            let k = q.trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty else { results = []; bgm = []; return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            busy = true
            async let a = FnClient.shared.search(k)
            async let b = Bangumi.search(k, animeOnly: false)
            results = MediaItem.list((try? await a) ?? [])
            bgm = Array(((try? await b) ?? []).prefix(20))
            busy = false
        }
    }
}

struct BgmCard: View {
    let s: JSON
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: Bangumi.img(s["images"]["large"].string ?? s["images"]["common"].string).flatMap(URL.init(string:)))
                .aspectRatio(contentMode: .fill).frame(width: 220, height: 320).clipShape(RoundedRectangle(cornerRadius: 18))
            Text(s["name_cn"].str.isEmpty ? s["name"].str : s["name_cn"].str).font(.system(size: 22, weight: .semibold)).lineLimit(1)
            HStack {
                if let sc = s["rating"]["score"].double ?? s["score"].double, sc > 0 { Text(String(format: "★ %.1f", sc)) }
                Text(s.first("date", "air_date").str.prefix(7))
            }
            .font(.system(size: 18)).foregroundStyle(.secondary)
        }
        .frame(width: 220)
        .focusable()
    }
}

struct FavoritesView: View {
    @State private var items: [MediaItem] = []
    @State private var loaded = false
    var body: some View {
        ZStack {
            AppBackground()
            if !loaded { LoadingView() }
            else if items.isEmpty { Text("还没有收藏").font(.title2).foregroundStyle(.secondary) }
            else {
                ScrollView {
                    VStack(alignment: .leading) {
                        Text("收藏").font(.system(size: 56, weight: .heavy)).padding(.bottom, 20)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 48), count: 6), spacing: 56) {
                            ForEach(items) { i in NavigationLink(value: OpenItem.route(i)) { PosterCardLabel(item: i) }.buttonStyle(CardButtonStyle()) }
                        }
                    }
                    .padding(80)
                }
            }
        }
        .task { items = MediaItem.list((try? await FnClient.shared.favorites()) ?? []); loaded = true }
    }
}

struct PersonView: View {
    let source: String
    let id: String
    let name: String
    @State private var info: JSON = .null
    @State private var works: [JSON] = []
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(alignment: .top, spacing: 50) {
                        RemoteImage(url: avatar).aspectRatio(contentMode: .fill).frame(width: 300, height: 400).clipShape(RoundedRectangle(cornerRadius: 26))
                        VStack(alignment: .leading, spacing: 16) {
                            Text(name).font(.system(size: 60, weight: .heavy))
                            Text(info.first("biography", "summary").str).font(.system(size: 24)).foregroundStyle(.secondary).lineLimit(10)
                        }
                        .focusable()
                    }
                    Text("作品").font(.system(size: 34, weight: .bold))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(220), spacing: 40), count: 7), spacing: 40) {
                        ForEach(works, id: \.self) { w in
                            VStack(alignment: .leading) {
                                RemoteImage(url: workCover(w)).aspectRatio(contentMode: .fill).frame(width: 220, height: 320).clipShape(RoundedRectangle(cornerRadius: 16))
                                Text(w.first("title", "name", "name_cn").str).lineLimit(1)
                                Text(w.first("character", "staff", "relation").str).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .focusable()
                        }
                    }
                }
                .padding(80)
            }
        }
        .task { await load() }
    }
    var avatar: URL? {
        if source == "TMDB" { return TMDB.img(info["profile_path"].string).flatMap(URL.init(string:)) }
        return Bangumi.img(info["images"]["large"].string).flatMap(URL.init(string:))
    }
    func workCover(_ w: JSON) -> URL? {
        if source == "TMDB" { return TMDB.img(w["poster_path"].string).flatMap(URL.init(string:)) }
        return Bangumi.img(w["image"].string ?? w["images"]["large"].string).flatMap(URL.init(string:))
    }
    func load() async {
        if source == "TMDB" {
            info = (try? await TMDB.person(id)) ?? .null
            works = info["combined_credits"]["cast"].array.sorted { ($0["popularity"].double ?? 0) > ($1["popularity"].double ?? 0) }.prefix(60).map { $0 }
        } else if source == "Bangumi" {
            let base = Bangumi.base
            info = (try? await Net.getJSON(URL(string: "\(base)/v0/persons/\(id)")!, headers: Bangumi.headers)) ?? .null
            if info.isNull { info = (try? await Net.getJSON(URL(string: "\(base)/v0/characters/\(id)")!, headers: Bangumi.headers)) ?? .null }
            works = ((try? await Net.getJSON(URL(string: "\(base)/v0/persons/\(id)/subjects")!, headers: Bangumi.headers)) ?? .null).array
            if works.isEmpty { works = ((try? await Net.getJSON(URL(string: "\(base)/v0/characters/\(id)/subjects")!, headers: Bangumi.headers)) ?? .null).array }
        }
    }
}

/// 手动匹配元数据（对应原项目 MetadataPickerModal / MetaEditModal）
struct MetaMatchView: View {
    let item: MediaItem
    let done: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var q = ""
    @State private var source = "Bangumi"
    @State private var hits: [JSON] = []
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("匹配元数据 · \(item.title)").font(.system(size: 44, weight: .bold))
            HStack(spacing: 20) {
                TextField("关键词", text: $q).frame(width: 800)
                ForEach(["Bangumi", "TMDB", "飞牛刮削"], id: \.self) { s in Chip(text: s, selected: source == s) { source = s; Task { await search() } } }
                Button("搜索") { Task { await search() } }.buttonStyle(GlassButtonStyle(prominent: true))
                Button("清除本地匹配") { MetaOverride.clear(item.guid); done(); dismiss() }.buttonStyle(GlassButtonStyle())
            }
            .focusSection()
            if busy { ProgressView() }
            ScrollView(.horizontal) {
                HStack(spacing: 36) {
                    ForEach(hits, id: \.self) { h in
                        Button { Task { await apply(h) } } label: {
                            VStack(alignment: .leading) {
                                RemoteImage(url: cover(h)).aspectRatio(contentMode: .fill).frame(width: 220, height: 320).clipShape(RoundedRectangle(cornerRadius: 16))
                                Text(h.first("name_cn", "title", "name").str).lineLimit(1).frame(width: 220, alignment: .leading)
                                Text(h.first("date", "release_date", "first_air_date", "air_date").str.prefix(4)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .padding(30)
            }
            .scrollClipDisabled()
        }
        .padding(70)
        .task { q = item.title; await search() }
    }
    func cover(_ h: JSON) -> URL? {
        switch source {
        case "Bangumi": return Bangumi.img(h["images"]["large"].string ?? h["images"]["common"].string).flatMap(URL.init(string:))
        case "TMDB": return TMDB.img(h["poster_path"].string).flatMap(URL.init(string:))
        default: return h["poster"].string.flatMap { $0.hasPrefix("http") ? URL(string: $0) : TMDB.img($0).flatMap(URL.init(string:)) }
        }
    }
    func search() async {
        busy = true; defer { busy = false }
        switch source {
        case "Bangumi": hits = (try? await Bangumi.search(q, animeOnly: false)) ?? []
        case "TMDB": hits = ((try? await TMDB.search(q, isTV: item.type != "Movie")) ?? [])
        default: hits = (try? await FnClient.shared.scrapSearch(keyword: q, itemGuid: item.guid)) ?? []
        }
    }
    func apply(_ h: JSON) async {
        switch source {
        case "Bangumi": MetaOverride.set(item.guid, source: "Bangumi", id: h["id"].str)
        case "TMDB": MetaOverride.set(item.guid, source: "TMDB", id: h["id"].str)
        default:
            try? await FnClient.shared.rescrap(itemGuid: item.guid, sourceId: h.first("source_id", "id").str,
                                               source: h["source"].string ?? "TMDB", type: item.type)
        }
        done(); dismiss()
    }
}
