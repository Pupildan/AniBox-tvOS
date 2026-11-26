import Foundation
import SwiftUI

struct DanmakuItem: Hashable {
    enum Mode { case scroll, top, bottom }
    let time: Double
    let mode: Mode
    let color: Color
    let text: String
}

/// 自建弹幕源（danmu_api / 弹弹play 兼容）：search/anime → bangumi/{id} → comment/{epId}
/// 多地址故障转移：仅传输层失败才切下一个地址（与原项目 danmaku/client.rs 一致）
enum DanmakuService {
    static var bases: [String] {
        AppSettings.shared.danmakuServers.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { $0.hasPrefix("http") }
    }

    static func get(_ path: String) async throws -> JSON {
        var lastErr: Error = FnError(message: "未配置弹幕源")
        for b in bases {
            guard let u = URL(string: b + path) else { continue }
            do {
                let (d, r) = try await Net.plain.data(from: u)
                if let h = r as? HTTPURLResponse, h.statusCode >= 400 { throw FnError(message: "弹幕源 HTTP \(h.statusCode)") }
                return JSON.parse(d)
            } catch let e as FnError { throw e }
            catch { lastErr = error; continue }
        }
        throw lastErr
    }

    static func searchAnime(_ keyword: String) async throws -> [JSON] {
        let k = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        return try await get("/api/v2/search/anime?keyword=\(k)")["animes"].array
    }
    static func episodes(animeId: String) async throws -> [JSON] {
        try await get("/api/v2/bangumi/\(animeId)")["bangumi"]["episodes"].array
    }
    static func comments(episodeId: String) async throws -> [DanmakuItem] {
        let d = try await get("/api/v2/comment/\(episodeId)?format=json&withRelated=true&chConvert=1")
        return parse(d["comments"].array)
    }
    static func parse(_ arr: [JSON]) -> [DanmakuItem] {
        let blocks = AppSettings.shared.danmakuBlockWords.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return arr.compactMap { c in
            let p = c["p"].str.split(separator: ",")
            let text = c["m"].str
            guard p.count >= 3, let t = Double(p[0]), !text.isEmpty else { return nil }
            if blocks.contains(where: { text.contains($0) }) { return nil }
            let mode: DanmakuItem.Mode = p[1] == "5" ? .top : (p[1] == "4" ? .bottom : .scroll)
            let rgb = Int(p[2]) ?? 0xFFFFFF
            let color = Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
            return DanmakuItem(time: t, mode: mode, color: color, text: text)
        }.sorted { $0.time < $1.time }
    }

    /// 自动匹配：按标题搜番剧，再按集号挑选
    static func autoMatch(title: String, episode: Int) async -> (label: String, items: [DanmakuItem])? {
        guard !bases.isEmpty else { return nil }
        let clean = title.replacingOccurrences(of: #"\s*(第.季|Season\s*\d+)$"#, with: "", options: .regularExpression)
        guard let animes = try? await searchAnime(clean), let a = animes.first(where: { $0["animeTitle"].str.contains(clean) }) ?? animes.first else { return nil }
        guard let eps = try? await episodes(animeId: a["animeId"].str ?? a["bangumiId"].str), !eps.isEmpty else { return nil }
        let idx = max(0, min(eps.count - 1, (episode > 0 ? episode : 1) - 1))
        let ep = eps.first(where: { $0["episodeNumber"].int == episode }) ?? eps[idx]
        guard let items = try? await comments(episodeId: ep["episodeId"].str) else { return nil }
        return ("\(a["animeTitle"].str) · \(ep["episodeTitle"].str)", items)
    }
}

/// 弹幕渲染层：TimelineView 每帧绘制，轨道分配避免重叠
final class DanmakuEngine: ObservableObject {
    @Published var items: [DanmakuItem] = []
    @Published var label = ""
    @Published var offset: Double = 0   // 手动时间轴偏移（秒）
    var lastIndex = 0
    struct Live { let item: DanmakuItem; let lane: Int; let start: Double; let width: CGFloat }
    var live: [Live] = []
    var laneFree: [Double] = []

    func load(_ list: [DanmakuItem], label: String) { items = list; self.label = label; reset() }
    func reset() { live.removeAll(); lastIndex = 0; laneFree.removeAll() }

    func tick(now t: Double, size: CGSize, settings: AppSettings) -> [Live] {
        let time = t + offset
        let lanesCount = max(1, Int(size.height * settings.danmakuArea / (settings.danmakuFontSize * 1.35)))
        if laneFree.count != lanesCount { laneFree = Array(repeating: -1, count: lanesCount) }
        let dur = 8.0 / settings.danmakuSpeed
        // 时间回跳（拖动进度）
        if let f = live.first, time < f.start - 1 { reset() }
        while lastIndex < items.count, items[lastIndex].time < time - 1 { lastIndex += 1 }
        var spawned = 0
        while lastIndex < items.count, items[lastIndex].time <= time {
            let it = items[lastIndex]; lastIndex += 1
            if it.mode == .top && !settings.danmakuShowTop { continue }
            if it.mode == .bottom && !settings.danmakuShowBottom { continue }
            if spawned > Int(settings.danmakuMaxPerSecond / 10) + 2 { continue }
            let w = CGFloat(it.text.count) * settings.danmakuFontSize
            if let lane = laneFree.indices.first(where: { laneFree[$0] <= time }) {
                laneFree[lane] = time + dur * Double(w + 60) / Double(size.width + w)
                live.append(Live(item: it, lane: lane, start: time, width: w)); spawned += 1
            }
        }
        live.removeAll { time - $0.start > ($0.item.mode == .scroll ? dur : 4) }
        return live
    }
}

struct DanmakuOverlay: View {
    @ObservedObject var engine: DanmakuEngine
    @EnvironmentObject var settings: AppSettings
    let currentTime: () -> Double
    let isPlaying: () -> Bool

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !settings.danmakuEnabled)) { _ in
                let t = currentTime()
                let lives = engine.tick(now: t, size: geo.size, settings: settings)
                let dur = 8.0 / settings.danmakuSpeed
                ZStack(alignment: .topLeading) {
                    ForEach(Array(lives.enumerated()), id: \.offset) { _, l in
                        let y = CGFloat(l.lane) * settings.danmakuFontSize * 1.35 + 40
                        let p = (t + engine.offset - l.start) / dur
                        Text(l.item.text)
                            .font(.system(size: settings.danmakuFontSize, weight: .semibold))
                            .foregroundStyle(l.item.color)
                            .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                            .fixedSize()
                            .position(x: l.item.mode == .scroll ? geo.size.width + l.width / 2 - CGFloat(p) * (geo.size.width + l.width) : geo.size.width / 2,
                                      y: l.item.mode == .bottom ? geo.size.height - y : y)
                    }
                }
                .opacity(settings.danmakuOpacity)
            }
        }
        .allowsHitTesting(false)
    }
}
