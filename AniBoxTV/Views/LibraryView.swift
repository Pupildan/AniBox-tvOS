import SwiftUI

struct LibrariesView: View {
    let libs: [Library]
    @State private var sum: JSON = .null
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("媒体库").font(.system(size: 56, weight: .heavy)).padding(.horizontal, 80)
                    if !sum.isNull {
                        HStack(spacing: 30) {
                            stat("电影", sum["movie"].int); stat("剧集", sum["tv"].int); stat("其它", sum["video"].int); stat("合计", sum["total"].int)
                        }
                        .padding(.horizontal, 80)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(520), spacing: 50), count: 3), spacing: 60) {
                        ForEach(libs) { l in
                            NavigationLink(value: Route.library(l)) {
                                ZStack(alignment: .bottomLeading) {
                                    HStack(spacing: 0) {
                                        ForEach(l.posters.prefix(3), id: \.self) { p in
                                            RemoteImage(url: FnClient.shared.imageURL(p, width: 300)).aspectRatio(contentMode: .fill)
                                                .frame(width: 520 / 3, height: 292).clipped()
                                        }
                                    }
                                    .frame(width: 520, height: 292)
                                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                                    VStack(alignment: .leading) {
                                        Text(l.name).font(.system(size: 34, weight: .bold))
                                        if let n = sum[l.id].int { Text("\(n) 项").foregroundStyle(.secondary) }
                                    }
                                    .padding(24)
                                }
                                .frame(width: 520, height: 292).glass(26).clipShape(RoundedRectangle(cornerRadius: 26))
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                    .padding(.horizontal, 80)
                }
                .padding(.vertical, 40)
            }
        }
        .task { sum = (try? await FnClient.shared.mediaSum()) ?? .null }
    }
    func stat(_ t: String, _ n: Int?) -> some View {
        VStack { Text("\(n ?? 0)").font(.system(size: 44, weight: .bold)); Text(t).foregroundStyle(.secondary) }
            .frame(width: 220, height: 130).glass(24)
    }
}

/// 媒体库内容：排序 + 类型筛选 + 分页无限加载
struct LibraryView: View {
    let library: Library
    @State private var items: [MediaItem] = []
    @State private var total = 0
    @State private var page = 1
    @State private var loading = false
    @State private var sort = "create_time"
    @State private var order = "DESC"
    @State private var genre: String?
    @State private var genres: [JSON] = []
    @State private var watchFilter = 0   // 0 全部 1 未看 2 已看

    let sorts = [("create_time", "添加时间"), ("release_date", "上映时间"), ("vote_average", "评分"), ("sort_title", "名称")]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text(library.name).font(.system(size: 56, weight: .heavy))
                        Text("\(total) 项").font(.title3).foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(sorts, id: \.0) { s in Chip(text: s.1, selected: sort == s.0) { sort = s.0; reload() } }
                            Chip(text: order == "DESC" ? "降序 ↓" : "升序 ↑") { order = order == "DESC" ? "ASC" : "DESC"; reload() }
                            Chip(text: ["全部", "未看", "已看"][watchFilter]) { watchFilter = (watchFilter + 1) % 3; reload() }
                            Chip(text: "全部类型", selected: genre == nil) { genre = nil; reload() }
                            ForEach(genres.prefix(20), id: \.self) { g in
                                Chip(text: g.first("value", "name").str, selected: genre == g["id"].str) { genre = g["id"].str; reload() }
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollClipDisabled()
                    .focusSection()
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 48), count: 6), spacing: 56) {
                        ForEach(items) { i in
                            NavigationLink(value: OpenItem.route(i)) { PosterCardLabel(item: i) }
                                .buttonStyle(CardButtonStyle())
                                .onAppear { if i.guid == items.last?.guid { Task { await more() } } }
                        }
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, 80).padding(.vertical, 40)
            }
        }
        .task {
            if items.isEmpty { await more() }
            genres = (try? await FnClient.shared.tagGenres()) ?? []
        }
    }
    func reload() { items = []; page = 1; total = 0; Task { await more() } }
    func more() async {
        guard !loading, page == 1 || items.count < total else { return }
        loading = true
        var tags: [String: Any] = [:]
        if let genre { tags["genres"] = [genre] }
        if watchFilter > 0 { tags["watched"] = watchFilter == 2 ? 1 : 0 }
        if let r = try? await FnClient.shared.items(ancestor: library.id, tags: tags, sortColumn: sort, sortType: order, page: page) {
            items += MediaItem.list(r.list); total = r.total; page += 1
        }
        loading = false
    }
}

/// 文件夹钻取（parent 查询）
struct FolderView: View {
    let folder: MediaItem
    @State private var items: [MediaItem] = []
    @State private var playing: MediaItem?
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text(folder.title).font(.system(size: 52, weight: .heavy))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 48), count: 6), spacing: 56) {
                        ForEach(items) { i in
                            if i.isFolder || i.isSeries || i.type == "Movie" {
                                NavigationLink(value: OpenItem.route(i)) { PosterCardLabel(item: i) }.buttonStyle(CardButtonStyle())
                            } else {
                                Button { playing = i } label: { PosterCardLabel(item: i) }.buttonStyle(CardButtonStyle())
                            }
                        }
                    }
                }
                .padding(80)
            }
        }
        .task {
            items = MediaItem.list((try? await FnClient.shared.items(parent: folder.guid, sortColumn: "sort_title", sortType: "ASC", pageSize: 200).list) ?? [])
        }
        .fullScreenCover(item: $playing) { i in PlayerView(item: i, playlist: items.filter { !$0.isFolder }) }
    }
}
