import SwiftUI

struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var carousel: [MediaItem] = []
    @State private var resume: [MediaItem] = []
    @State private var libs: [Library] = []
    @State private var shelves: [(Library, [MediaItem])] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var heroIndex = 0
    @State private var playing: MediaItem?

    var body: some View {
        ZStack {
            AppBackground(image: FnClient.shared.imageURL(carousel[safe: heroIndex]?.backdrop, width: 1280))
            if let error, !loaded { ErrorView(message: error) { Task { await load() } } }
            else if !loaded { LoadingView() }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        if settings.showCarousel && !carousel.isEmpty { hero }
                        if !resume.isEmpty {
                            ShelfRow(title: "继续观看") {
                                ForEach(resume) { i in
                                    PosterCard(item: i, width: 460, landscape: true) { playing = i }
                                        .contextMenu { Button("查看详情") { } }
                                }
                            }
                        }
                        ForEach(shelves, id: \.0.id) { lib, items in
                            ShelfRow(title: lib.name, trailing: "最近添加") {
                                ForEach(items) { i in
                                    NavigationLink(value: OpenItem.route(i)) { PosterCardLabel(item: i) }
                                        .buttonStyle(CardButtonStyle())
                                }
                                NavigationLink(value: Route.library(lib)) {
                                    VStack { Image(systemName: "arrow.right.circle.fill").font(.system(size: 60)); Text("查看全部") }
                                        .frame(width: 260, height: 390).glass(18)
                                }
                                .buttonStyle(CardButtonStyle())
                            }
                        }
                    }
                    .padding(.bottom, 80)
                }
            }
        }
        .task { if !loaded { await load() } }
        .fullScreenCover(item: $playing) { i in PlayerView(item: i, playlist: []) }
    }

    var hero: some View {
        let i = carousel[heroIndex]
        return ZStack(alignment: .bottomLeading) {
            RemoteImage(url: FnClient.shared.imageURL(i.backdrop ?? i.poster, width: 1920))
                .aspectRatio(contentMode: .fill).frame(height: 760).clipped()
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 18) {
                Text(i.title).font(.system(size: 72, weight: .heavy)).lineLimit(1)
                Text(i.subtitleLine).font(.title3).foregroundStyle(.secondary)
                Text(i.overview).font(.system(size: 26)).lineLimit(3).frame(maxWidth: 1100, alignment: .leading)
                HStack(spacing: 24) {
                    Button { playing = i } label: { Label("播放", systemImage: "play.fill") }.buttonStyle(GlassButtonStyle(prominent: true))
                    NavigationLink(value: OpenItem.route(i)) { Label("详情", systemImage: "info.circle") }.buttonStyle(GlassButtonStyle())
                    Button { heroIndex = (heroIndex + carousel.count - 1) % carousel.count } label: { Image(systemName: "chevron.left") }.buttonStyle(GlassButtonStyle())
                    Button { heroIndex = (heroIndex + 1) % carousel.count } label: { Image(systemName: "chevron.right") }.buttonStyle(GlassButtonStyle())
                    Text("\(heroIndex + 1) / \(carousel.count)").foregroundStyle(.secondary)
                }
                .focusSection()
            }
            .padding(.horizontal, 80).padding(.bottom, 50)
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .task(id: heroIndex) {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if !carousel.isEmpty { withAnimation(.easeInOut(duration: 0.8)) { heroIndex = (heroIndex + 1) % carousel.count } }
        }
    }

    func load() async {
        error = nil
        do {
            async let c = FnClient.shared.items(types: ["Movie", "TV"], pageSize: 24)
            async let r = FnClient.shared.continueWatching()
            async let l = FnClient.shared.mediaLibs()
            let (cv, rv, lv) = try await (c, r, l)
            carousel = Array(MediaItem.list(cv.list).filter { $0.backdrop != nil }.prefix(10))
            resume = MediaItem.list(rv)
            libs = Library.list(lv)
            loaded = true
            var s: [(Library, [MediaItem])] = []
            for lib in libs {
                if let r = try? await FnClient.shared.items(ancestor: lib.id, pageSize: 20) {
                    let items = MediaItem.list(r.list).filter { !settings.hideWatched || !$0.watched }
                    if !items.isEmpty { s.append((lib, items)) }
                }
            }
            shelves = s
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PosterCardLabel: View {
    let item: MediaItem
    var width: CGFloat = 260
    @Environment(\.isFocused) var focused
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RemoteImage(url: FnClient.shared.imageURL(item.poster ?? item.backdrop))
                    .aspectRatio(contentMode: .fill).frame(width: width, height: width * 1.5).clipped()
                if let r = item.rating, r > 0 {
                    Text(String(format: "%.1f", r)).font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 4).glass(10).padding(10)
                }
                if item.watched {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                        .padding(12).frame(width: width, alignment: .trailing)
                }
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: settings.posterCornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: settings.posterCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.9 : 0.08), lineWidth: focused ? 4 : 1))
            Text(item.title).font(.system(size: 24, weight: .semibold)).lineLimit(1).frame(width: width, alignment: .leading)
            Text(item.subtitleLine).font(.system(size: 20)).foregroundStyle(.secondary).lineLimit(1).frame(width: width, alignment: .leading)
        }
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
