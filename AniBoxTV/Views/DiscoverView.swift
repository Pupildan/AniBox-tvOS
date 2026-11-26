import SwiftUI

/// 发现：Bangumi 每日放送 / 往季番表 / Bangumi 账号收藏（对应原项目 discover/*）
struct DiscoverView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var tab = 0
    @State private var calendar: [JSON] = []
    @State private var day = (Calendar.current.component(.weekday, from: Date()) + 5) % 7 + 1
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var quarter = (Calendar.current.component(.month, from: Date()) - 1) / 3
    @State private var season: [JSON] = []
    @State private var me: JSON = .null
    @State private var collection: [JSON] = []
    @State private var collType = 3
    @State private var owned: [String: MediaItem] = [:]
    @State private var error: String?

    let days = ["一", "二", "三", "四", "五", "六", "日"]
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 18) {
                        Text("发现").font(.system(size: 56, weight: .heavy)).padding(.trailing, 30)
                        Chip(text: "每日放送", selected: tab == 0) { tab = 0 }
                        Chip(text: "季度番表", selected: tab == 1) { tab = 1; Task { await loadSeason() } }
                        Chip(text: "我的 Bangumi", selected: tab == 2) { tab = 2; Task { await loadMe() } }
                    }
                    .focusSection()
                    if let error { Text(error).foregroundStyle(.red) }
                    switch tab {
                    case 0: calendarView
                    case 1: seasonView
                    default: meView
                    }
                }
                .padding(80)
            }
        }
        .task { await loadCalendar() }
    }

    var calendarView: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) { ForEach(1...7, id: \.self) { d in Chip(text: "周" + days[d - 1], selected: day == d) { day = d } } }.focusSection()
            let items = calendar.first(where: { $0["weekday"]["id"].int == day })?["items"].array ?? []
            grid(items)
        }
    }
    var seasonView: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Chip(text: "◀ \(year - 1)") { year -= 1; Task { await loadSeason() } }
                ForEach(0..<4) { q in Chip(text: "\(year) \(["冬", "春", "夏", "秋"][q])", selected: quarter == q) { quarter = q; Task { await loadSeason() } } }
                Chip(text: "\(year + 1) ▶") { year += 1; Task { await loadSeason() } }
            }
            .focusSection()
            grid(season)
        }
    }
    var meView: some View {
        VStack(alignment: .leading, spacing: 24) {
            if settings.bgmToken.isEmpty {
                Text("在「设置 → 元数据」填入 Bangumi Access Token 后可同步收藏与进度（在 bgm.tv/dev/app 生成）").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 20) {
                    RemoteImage(url: Bangumi.img(me["avatar"]["large"].string).flatMap(URL.init(string:))).frame(width: 90, height: 90).clipShape(Circle())
                    Text(me["nickname"].str).font(.title2)
                    ForEach([(1, "想看"), (3, "在看"), (2, "看过"), (4, "搁置"), (5, "抛弃")], id: \.0) { t in
                        Chip(text: t.1, selected: collType == t.0) { collType = t.0; Task { await loadMe() } }
                    }
                }
                .focusSection()
                grid(collection.map { $0["subject"] })
            }
        }
    }

    func grid(_ items: [JSON]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(240), spacing: 44), count: 6), spacing: 50) {
            ForEach(items, id: \.self) { s in
                let name = s["name_cn"].str.isEmpty ? s["name"].str : s["name_cn"].str
                if let mine = owned[name] {
                    NavigationLink(value: OpenItem.route(mine)) { BgmTile(s: s, inLibrary: true) }.buttonStyle(CardButtonStyle())
                } else {
                    Button {} label: { BgmTile(s: s, inLibrary: false) }.buttonStyle(CardButtonStyle())
                }
            }
        }
    }

    func loadCalendar() async {
        do { calendar = try await Bangumi.calendar(); await matchOwned(calendar.flatMap { $0["items"].array }) }
        catch { self.error = "Bangumi 加载失败：\(error.localizedDescription)" }
    }
    func loadSeason() async {
        season = (try? await Bangumi.season(year: year, month: quarter * 3 + 1)) ?? []
        await matchOwned(season)
    }
    func loadMe() async {
        guard !settings.bgmToken.isEmpty else { return }
        do {
            me = try await Bangumi.me()
            collection = try await Bangumi.collection(username: me["username"].str, type: collType)
            await matchOwned(collection.map { $0["subject"] })
        } catch { self.error = "Bangumi 账号：\(error.localizedDescription)" }
    }
    /// 「库内已有」标记：与飞牛库内标题匹配（对应原项目 libMatch）
    func matchOwned(_ subjects: [JSON]) async {
        if owned.isEmpty, let r = try? await FnClient.shared.items(types: ["TV", "Movie"], pageSize: 500) {
            for i in MediaItem.list(r.list) { owned[i.title] = i }
        }
    }
}

struct BgmTile: View {
    let s: JSON
    let inLibrary: Bool
    @Environment(\.isFocused) var focused
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(url: Bangumi.img(s["images"]["large"].string ?? s["images"]["common"].string).flatMap(URL.init(string:)))
                    .aspectRatio(contentMode: .fill).frame(width: 240, height: 340).clipped()
                if inLibrary { Text("库内").font(.system(size: 18, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 4).glass(10, tint: .green).padding(10) }
            }
            .frame(width: 240, height: 340).clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(focused ? 0.9 : 0.08), lineWidth: focused ? 4 : 1))
            Text(s["name_cn"].str.isEmpty ? s["name"].str : s["name_cn"].str).font(.system(size: 22, weight: .semibold)).lineLimit(1)
            HStack {
                if let sc = s["rating"]["score"].double ?? s["score"].double, sc > 0 { Text(String(format: "★ %.1f", sc)) }
                if let r = s["rank"].int ?? s["rating"]["rank"].int, r > 0 { Text("#\(r)") }
            }
            .font(.system(size: 18)).foregroundStyle(.secondary)
        }
        .frame(width: 240)
    }
}

/// 电视直播：飞牛 LiveChannel 库 + 自定义 M3U 订阅
struct LiveView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var channels: [IPTVChannel] = []
    @State private var nasLive: [MediaItem] = []
    @State private var group = "全部"
    @State private var playing: MediaItem?
    @State private var error: String?
    var groups: [String] { ["全部"] + Array(Set(channels.map { $0.group })).sorted() }
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("电视直播").font(.system(size: 56, weight: .heavy))
                    if !nasLive.isEmpty {
                        ShelfRow(title: "飞牛直播频道") {
                            ForEach(nasLive) { i in Button { playing = i } label: { PosterCardLabel(item: i, width: 220) }.buttonStyle(CardButtonStyle()) }
                        }
                        .padding(.horizontal, -80)
                    }
                    if settings.iptvURL.isEmpty {
                        Text("在「设置 → 直播」填入 M3U / TXT 订阅地址即可观看 IPTV").foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) { HStack(spacing: 14) { ForEach(groups, id: \.self) { g in Chip(text: g, selected: group == g) { group = g } } }.padding(.vertical, 20) }
                            .scrollClipDisabled().focusSection()
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(330), spacing: 36), count: 5), spacing: 36) {
                            ForEach(channels.filter { group == "全部" || $0.group == group }) { c in
                                Button {
                                    playing = MediaItem(raw: .object(["guid": .string(c.url), "title": .string(c.name), "type": .string("LiveChannel"), "url": .string(c.url)]))
                                } label: {
                                    HStack(spacing: 16) {
                                        RemoteImage(url: c.logo.flatMap(URL.init(string:))).aspectRatio(contentMode: .fit).frame(width: 80, height: 60)
                                        Text(c.name).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(20).frame(width: 330, height: 100).glass(20)
                                }
                                .buttonStyle(CardButtonStyle())
                            }
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .padding(80)
            }
        }
        .task(id: settings.iptvURL) {
            nasLive = MediaItem.list((try? await FnClient.shared.items(types: ["LiveChannel"], pageSize: 200).list) ?? [])
            guard !settings.iptvURL.isEmpty else { return }
            do { channels = try await IPTV.load(settings.iptvURL) } catch { self.error = error.localizedDescription }
        }
        .fullScreenCover(item: $playing) { i in
            PlayerView(item: i, playlist: [])
        }
    }
}
