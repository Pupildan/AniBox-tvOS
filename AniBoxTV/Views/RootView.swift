import SwiftUI

enum NavTab: String, CaseIterable, Identifiable {
    case home, library, discover, live, history, favorites, search, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "首页"; case .library: "媒体库"; case .discover: "发现"; case .live: "直播"
        case .history: "观影记录"; case .favorites: "收藏"; case .search: "搜索"; case .settings: "设置"
        }
    }
    var icon: String {
        switch self {
        case .home: "house.fill"; case .library: "square.grid.2x2.fill"; case .discover: "sparkles.tv.fill"; case .live: "antenna.radiowaves.left.and.right"
        case .history: "clock.arrow.circlepath"; case .favorites: "heart.fill"; case .search: "magnifyingglass"; case .settings: "gearshape.fill"
        }
    }
}

/// 路由：所有页面通过 NavigationStack 推入，菜单键自然返回
enum Route: Hashable {
    case detail(MediaItem)
    case library(Library)
    case folder(MediaItem)
    case person(source: String, id: String, name: String)
    case report
}

struct RootView: View {
    @EnvironmentObject var session: Session
    @State private var tab: NavTab = .home
    @State private var libs: [Library] = []

    var body: some View {
        TabView(selection: $tab) {
            ForEach(NavTab.allCases) { t in
                NavigationStack {
                    page(t)
                        .navigationDestination(for: Route.self) { r in destination(r) }
                }
                .tabItem { Label(t.title, systemImage: t.icon) }
                .tag(t)
            }
        }
        .task { libs = Library.list((try? await FnClient.shared.mediaLibs()) ?? []) }
        .alert("登录已过期", isPresented: $session.expiredNotice) { Button("好") {} } message: { Text("请重新登录") }
    }

    @ViewBuilder func page(_ t: NavTab) -> some View {
        switch t {
        case .home: HomeView()
        case .library: LibrariesView(libs: libs)
        case .discover: DiscoverView()
        case .live: LiveView()
        case .history: HistoryView()
        case .favorites: FavoritesView()
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }
    @ViewBuilder func destination(_ r: Route) -> some View {
        switch r {
        case .detail(let i): DetailView(item: i)
        case .library(let l): LibraryView(library: l)
        case .folder(let f): FolderView(folder: f)
        case .person(let s, let id, let n): PersonView(source: s, id: id, name: n)
        case .report: WatchReportView()
        }
    }
}

extension Library { static func list(_ a: [JSON]) -> [Library] { a.map { Library(raw: $0) } } }

/// 统一打开条目：剧/电影进详情，文件夹钻取，单视频直接播
struct OpenItem {
    static func route(_ i: MediaItem) -> Route { i.isFolder ? .folder(i) : .detail(i) }
}
