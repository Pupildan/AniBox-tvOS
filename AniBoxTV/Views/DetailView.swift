import SwiftUI

struct DetailView: View {
    let item: MediaItem
    @EnvironmentObject var settings: AppSettings
    @State private var detail: MediaItem?
    @State private var seasons: [MediaItem] = []
    @State private var season: MediaItem?
    @State private var episodes: [MediaItem] = []
    @State private var meta: [ExtMeta] = []
    @State private var metaTab = 0
    @State private var versions: [JSON] = []
    @State private var playing: (MediaItem, [MediaItem])?
    @State private var showPlayer = false
    @State private var favorite = false
    @State private var watched = false
    @State private var showMatch = false
    @State private var toast: String?
    @State private var tmdbStills: [Int: String] = [:]

    var d: MediaItem { detail ?? item }
    var isTV: Bool { d.type == "TV" || !seasons.isEmpty }
    var bg: URL? {
        if let b = meta.first(where: { $0.banner != nil })?.banner { return URL(string: b) }
        return FnClient.shared.imageURL(d.backdrop ?? d.poster, width: 1920)
    }

    var body: some View {
        ZStack {
            AppBackground(image: bg)
            ScrollView {
                VStack(alignment: .leading, spacing: 46) {
                    header
                    if isTV { seasonSection }
                    if versions.count > 1 { versionSection }
                    metaSection
                }
                .padding(.bottom, 100)
            }
            if let toast { Text(toast).padding(24).glass(20).frame(maxHeight: .infinity, alignment: .bottom).padding(60) }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $showPlayer) {
            if let p = playing { PlayerView(item: p.0, playlist: p.1) }
        }
        .sheet(isPresented: $showMatch) { MetaMatchView(item: d) { Task { await loadMeta(force: true) } } }
    }

    // MARK: 头部
    var header: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: bg).aspectRatio(contentMode: .fill).frame(height: 820).clipped()
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                .overlay(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .leading, endPoint: .center))
            HStack(alignment: .bottom, spacing: 50) {
                if settings.detailStyle == "editorial" {
                    RemoteImage(url: FnClient.shared.imageURL(d.poster)).aspectRatio(2/3, contentMode: .fill)
                        .frame(width: 340, height: 510).clipShape(RoundedRectangle(cornerRadius: 24)).shadow(radius: 30)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text(d.title).font(.system(size: settings.detailStyle == "editorial" ? 64 : 80, weight: .heavy)).lineLimit(2)
                    if let o = meta.first?.originalTitle, !o.isEmpty, o != d.title { Text(o).font(.title3).foregroundStyle(.secondary) }
                    HStack(spacing: 18) {
                        if !d.year.isEmpty { tag(d.year) }
                        if let r = d.rating, r > 0 { tag(String(format: "飞牛 ★ %.1f", r)) }
                        ForEach(meta, id: \.source) { m in if let s = m.score, s > 0 { tag(String(format: "%@ ★ %.1f", m.source, s)) } }
                        if let rank = meta.first(where: { $0.source == "Bangumi" })?.rank, rank > 0 { tag("Rank #\(rank)") }
                    }
                    let gs = d.genres.isEmpty ? (meta.first?.tags.prefix(6).map { $0 } ?? []) : d.genres
                    if !gs.isEmpty { Text(gs.joined(separator: " / ")).foregroundStyle(.secondary) }
                    Text(d.overview.isEmpty ? (meta.first?.summary ?? "") : d.overview)
                        .font(.system(size: 26)).lineLimit(4).frame(maxWidth: 1200, alignment: .leading)
                    HStack(spacing: 24) {
                        Button { Task { await playDefault() } } label: {
                            Label(resumeLabel, systemImage: "play.fill")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                        .prefersDefaultFocus(true, in: ns)
                        Button { Task { await toggleFav() } } label: { Image(systemName: favorite ? "heart.fill" : "heart") }
                            .buttonStyle(GlassButtonStyle())
                        Button { Task { await toggleWatched() } } label: { Image(systemName: watched ? "checkmark.circle.fill" : "checkmark.circle") }
                            .buttonStyle(GlassButtonStyle())
                        Button { showMatch = true } label: { Label("匹配元数据", systemImage: "wand.and.stars") }
                            .buttonStyle(GlassButtonStyle())
                        Button { Task { try? await FnClient.shared.refreshItem(d.guid); flash("已提交刷新") } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(GlassButtonStyle())
                    }
                    .focusSection()
                }
            }
            .padding(.horizontal, 80).padding(.bottom, 40)
        }
        .focusScope(ns)
    }
    @Namespace var ns

    var resumeLabel: String {
        if d.ts > 5 { return "继续播放 \(PlayerModel.fmt(d.ts))" }
        return isTV ? "播放" : "播放"
    }
    func tag(_ s: String) -> some View { Text(s).font(.system(size: 22, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 6).glass(12) }

    // MARK: 季/集
    var seasonSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(seasons) { s in
                            Chip(text: s.title.isEmpty ? "第 \(s.season) 季" : s.title, selected: s.guid == season?.guid) {
                                season = s; Task { await loadEpisodes() }
                            }
                        }
                    }
                    .padding(.horizontal, 80).padding(.vertical, 20)
                }
                .scrollClipDisabled()
                .focusSection()
            }
            ShelfRow(title: "剧集", trailing: "\(episodes.count) 集") {
                ForEach(episodes) { e in
                    Button { play(e, list: episodes) } label: { EpisodeCard(ep: e, still: tmdbStills[e.episode]) }
                        .buttonStyle(CardButtonStyle())
                        .contextMenu {
                            Button(e.watched ? "标为未看" : "标为已看") { Task { try? await FnClient.shared.setWatched(e.guid, watched: !e.watched); await loadEpisodes() } }
                            Button("从头播放") { play(e, list: episodes, fromStart: true) }
                        }
                }
            }
            .defaultScrollAnchor(.leading)
        }
    }

    var versionSection: some View {
        ShelfRow(title: "版本", trailing: "\(versions.count) 个文件") {
            ForEach(versions, id: \.self) { v in
                Button {
                    var it = d; _ = it
                    playing = (d, []); UserDefaults.standard.set(v["media_guid"].str, forKey: "ver.\(d.guid)"); showPlayer = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(v["resolution_type"].string ?? "\(v["width"].int ?? 0)×\(v["height"].int ?? 0)").font(.system(size: 30, weight: .bold))
                        Text([v["codec_name"].str.uppercased(), v["color_range_type"].str, v["title"].str].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(26).frame(width: 420, height: 170, alignment: .leading).glass(24)
                }
                .buttonStyle(CardButtonStyle())
            }
        }
    }

    // MARK: 元数据聚合
    var metaSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !meta.isEmpty {
                HStack(spacing: 18) {
                    ForEach(Array(meta.enumerated()), id: \.offset) { i, m in Chip(text: m.source, selected: metaTab == i) { metaTab = i } }
                }
                .padding(.horizontal, 80).focusSection()
                let m = meta[min(metaTab, meta.count - 1)]
                if !m.summary.isEmpty {
                    Text(m.summary).font(.system(size: 24)).foregroundStyle(.secondary).lineLimit(8)
                        .padding(36).frame(maxWidth: 1700, alignment: .leading).glass(28).padding(.horizontal, 80)
                        .focusable()
                }
                if !m.cast.isEmpty {
                    ShelfRow(title: m.source == "TMDB" ? "演员" : "角色 / 声优") {
                        ForEach(m.cast) { p in
                            NavigationLink(value: Route.person(source: m.source, id: p.id, name: p.name)) { PersonCardLabel(person: p) }
                                .buttonStyle(CardButtonStyle())
                        }
                    }
                }
                if !m.staff.isEmpty {
                    ShelfRow(title: "制作人员") {
                        ForEach(m.staff) { p in
                            NavigationLink(value: Route.person(source: m.source, id: p.id, name: p.name)) { PersonCardLabel(person: p) }
                                .buttonStyle(CardButtonStyle())
                        }
                    }
                }
                if !m.related.isEmpty {
                    ShelfRow(title: m.source == "TMDB" ? "相关推荐" : "关联条目") {
                        ForEach(m.related, id: \.self) { r in
                            VStack(alignment: .leading) {
                                RemoteImage(url: r.cover.flatMap(URL.init(string:))).aspectRatio(contentMode: .fill)
                                    .frame(width: 220, height: 330).clipShape(RoundedRectangle(cornerRadius: 18))
                                Text(r.title).lineLimit(1).frame(width: 220, alignment: .leading)
                                Text(r.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .focusable()
                        }
                    }
                }
            }
        }
    }

    // MARK: 数据
    func load() async {
        if let x = try? await FnClient.shared.item(item.guid) { detail = MediaItem(raw: x) }
        favorite = d.favorite; watched = d.watched
        if d.type == "TV" || item.type == "TV" {
            seasons = MediaItem.list((try? await FnClient.shared.seasons(d.guid)) ?? [])
            season = seasons.first(where: { s in s.ts > 0 }) ?? seasons.first
            await loadEpisodes()
        } else if d.type == "Season" {
            season = d; await loadEpisodes()
        } else {
            versions = (try? await FnClient.shared.streamList(d.guid))?["video_streams"].array ?? []
        }
        await loadMeta()
    }
    func loadEpisodes() async {
        guard let s = season else { return }
        episodes = MediaItem.list((try? await FnClient.shared.episodes(s.guid)) ?? [])
        if !d.tmdbId.isEmpty, let st = try? await TMDB.seasonStills(id: d.tmdbId, season: s.season) {
            var m: [Int: String] = [:]
            for e in st { if let p = TMDB.img(e["still_path"].string, "w500") { m[e["episode_number"].int ?? 0] = p } }
            tmdbStills = m
        }
    }
    func loadMeta(force: Bool = false) async {
        var out: [ExtMeta] = []
        let title = d.title
        let ov = MetaOverride.get(d.guid)
        if settings.useBangumi {
            if let ov, ov.source == "Bangumi", let s = try? await Bangumi.subject(ov.id) { out.append(Bangumi.toMeta(s)) }
            else if let b = await Bangumi.match(title: title, year: d.year) { out.append(b) }
        }
        if settings.useTMDB, !settings.tmdbKey.isEmpty {
            let tid = (ov?.source == "TMDB" ? ov?.id : nil) ?? d.tmdbId
            if !tid.isEmpty, let x = try? await TMDB.details(id: tid, isTV: isTV) { out.append(TMDB.toMeta(x, isTV: isTV)) }
            else if let f = try? await TMDB.search(title, isTV: isTV).first, let x = try? await TMDB.details(id: f["id"].str, isTV: isTV) {
                out.append(TMDB.toMeta(x, isTV: isTV))
            }
        }
        if settings.useAniList, let a = await AniList.search(title) { out.append(a) }
        meta = out
    }

    func playDefault() async {
        if isTV {
            let target = episodes.first(where: { $0.ts > 5 && !$0.watched }) ?? episodes.first(where: { !$0.watched }) ?? episodes.first
            if let t = target { play(t, list: episodes) }
        } else { play(d, list: []) }
    }
    func play(_ e: MediaItem, list: [MediaItem], fromStart: Bool = false) {
        var it = e
        if fromStart, case .object(var o) = e.raw { o["ts"] = .number(0); it = MediaItem(raw: .object(o)) }
        playing = (it, list); showPlayer = true
    }
    func toggleFav() async {
        do { try await FnClient.shared.setFavorite(d.guid, fav: !favorite); favorite.toggle(); flash(favorite ? "已收藏" : "已取消收藏") }
        catch { flash(error.localizedDescription) }
    }
    func toggleWatched() async {
        do { try await FnClient.shared.setWatched(d.guid, watched: !watched); watched.toggle(); flash(watched ? "已标为看过" : "已标为未看") }
        catch { flash(error.localizedDescription) }
    }
    func flash(_ s: String) { toast = s; Task { try? await Task.sleep(nanoseconds: 2_000_000_000); toast = nil } }
}

struct EpisodeCard: View {
    let ep: MediaItem
    let still: String?
    @Environment(\.isFocused) var focused
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: still.flatMap(URL.init(string:)) ?? FnClient.shared.imageURL(ep.backdrop ?? ep.poster, width: 800))
                    .aspectRatio(contentMode: .fill).frame(width: 420, height: 236).clipped()
                if ep.progress > 0.01 {
                    Capsule().fill(.white).frame(width: 392 * ep.progress, height: 6).padding(14)
                }
                if ep.watched { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing) }
            }
            .frame(width: 420, height: 236).clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(focused ? 0.9 : 0.1), lineWidth: focused ? 4 : 1))
            Text("\(ep.episode). \(ep.title)").font(.system(size: 24, weight: .semibold)).lineLimit(1).frame(width: 420, alignment: .leading)
            if focused && !ep.overview.isEmpty { Text(ep.overview).font(.system(size: 19)).foregroundStyle(.secondary).lineLimit(2).frame(width: 420, alignment: .leading) }
        }
    }
}

struct PersonCardLabel: View {
    let person: ExtMeta.Person
    @Environment(\.isFocused) var focused
    var body: some View {
        VStack(spacing: 10) {
            RemoteImage(url: person.avatar.flatMap(URL.init(string:)))
                .aspectRatio(contentMode: .fill).frame(width: 170, height: 170).clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 4))
            Text(person.name).font(.system(size: 22, weight: .semibold)).lineLimit(1)
            Text(person.role).font(.system(size: 18)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 200)
    }
}
