import Foundation
import SwiftUI

@MainActor
final class PlayerModel: ObservableObject {
    let engine: PlayerEngine
    let danmaku = DanmakuEngine()
    @Published var item: MediaItem
    @Published var playlist: [MediaItem]
    @Published var title = ""
    @Published var subtitle = ""
    @Published var error: String?
    @Published var loading = true
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var playing = false
    @Published var buffering = false
    @Published var skipOpening = 0
    @Published var skipEnding = 0
    @Published var versions: [JSON] = []
    @Published var selectedMedia: String?
    @Published var nasSubtitles: [JSON] = []
    @Published var toast: String?
    @Published var speed: Double = AppSettings.shared.defaultSpeed { didSet { engine.rate = speed } }

    private var playInfo: JSON = .null
    private var timer: Timer?
    private var lastReport = Date()
    private var watchedAccum: Double = 0
    private var lastTick: Double = 0
    private var skippedOpening = false
    private var endingHandled = false

    init(item: MediaItem, playlist: [MediaItem] = []) {
        self.item = item
        self.playlist = playlist
        self.engine = EngineFactory.make()
        engine.rate = speed
    }

    var index: Int? { playlist.firstIndex { $0.guid == item.guid } }
    var hasNext: Bool { (index.map { $0 + 1 < playlist.count }) ?? false }
    var hasPrev: Bool { (index.map { $0 > 0 }) ?? false }

    func start(resume: Bool = true) async {
        loading = true; error = nil; skippedOpening = false; endingHandled = false
        title = item.tvTitle.isEmpty ? item.title : item.tvTitle
        subtitle = item.tvTitle.isEmpty ? item.subtitleLine : (item.episode > 0 ? "第 \(item.episode) 集 · \(item.title)" : item.title)
        do {
            if item.isLive || item.raw["url"].string != nil {
                if let u = URL(string: item.raw["url"].str) { engine.load(url: u, headers: [:], start: 0) }
                loading = false; startTimer(); return
            }
            let info = try await FnClient.shared.playInfo(item.guid, mediaGuid: selectedMedia)
            playInfo = info
            skipOpening = info["play_config"]["skip_opening"].int ?? 0
            skipEnding = info["play_config"]["skip_ending"].int ?? 0
            let playGuid = info["guid"].string ?? item.guid
            let list = try? await FnClient.shared.streamList(playGuid)
            versions = list?["video_streams"].array ?? []
            nasSubtitles = list?["subtitle_streams"].array ?? []
            var media = selectedMedia ?? info["media_guid"].string ?? versions.first?["media_guid"].string ?? ""
            if media.isEmpty { media = playGuid }
            selectedMedia = media

            var url = FnClient.shared.mediaURL(mediaGuid: media)!
            var headers = FnClient.shared.authHeaders(token: Session.shared.token)
            // 云盘直链（115/夸克/阿里等）：fnOS 下发 direct_link_qualities 时直连
            if let s = try? await FnClient.shared.stream(mediaGuid: media),
               s["cloud_storage_info"].isNull == false,
               let direct = s["direct_link_qualities"][0]["url"].string, let du = URL(string: direct) {
                url = du
                headers = [:]
                let ck = s["header"]["Cookie"].array.compactMap { $0.string }.joined(separator: "; ")
                if !ck.isEmpty { headers["Cookie"] = ck }
                headers["User-Agent"] = s["header"]["User-Agent"][0].string ?? "Mozilla/5.0 (AppleTV) AppleWebKit/605.1.15"
            }
            var startAt = 0.0
            if resume {
                let ts = info["ts"].double ?? item.ts
                if ts > 5 { startAt = ts }
            }
            if startAt < 1, AppSettings.shared.autoSkipOpening, skipOpening > 0 { startAt = Double(skipOpening); skippedOpening = true }
            engine.load(url: url, headers: headers, start: startAt)
            loading = false
            startTimer()
            await loadExternalSubtitle()
            Task { await loadDanmaku() }
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }

    private func loadExternalSubtitle() async {
        // 外挂字幕（NAS 端外置/提取字幕），MPV 内核下以 sub-add 挂载
        let external = nasSubtitles.filter { $0["is_external"].bool }
        for s in external.prefix(4) {
            if let u = FnClient.shared.subtitleURL(s["guid"].str), let d = try? await FnClient.shared.download(u) {
                let f = FileManager.default.temporaryDirectory.appendingPathComponent("\(s["guid"].str).\(s["format"].string ?? "srt")")
                try? d.write(to: f)
                engine.addSubtitle(url: f)
            }
        }
    }

    func loadDanmaku() async {
        guard AppSettings.shared.danmakuEnabled else { return }
        let name = item.tvTitle.isEmpty ? item.title : item.tvTitle
        if let r = await DanmakuService.autoMatch(title: name, episode: item.episode) {
            danmaku.load(r.items, label: r.label)
            toast = "已加载弹幕 \(r.items.count) 条"
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func tick() {
        time = engine.currentTime; duration = engine.duration
        playing = engine.isPlaying; buffering = engine.isBuffering
        if playing, time > lastTick, time - lastTick < 3 { watchedAccum += time - lastTick }
        lastTick = time
        if Date().timeIntervalSince(lastReport) > 15 { report() }
        if duration > 0, !endingHandled {
            let endAt = skipEnding > 0 ? duration - Double(skipEnding) : duration - 0.8
            if time >= endAt {
                endingHandled = true
                if skipEnding > 0 && AppSettings.shared.autoSkipEnding || time >= duration - 0.8 { finish() }
            }
        }
    }
    func report() {
        lastReport = Date()
        guard !item.isLive, duration > 0 else { return }
        let g = playInfo["guid"].string ?? item.guid
        let t = time, d = duration, info = playInfo
        Task { await FnClient.shared.recordPlay(itemGuid: g, info: info, ts: t, duration: d) }
    }
    private func finish() {
        report()
        flushHistory(finished: true)
        if AppSettings.shared.autoNextEpisode && hasNext { next() }
    }
    func flushHistory(finished: Bool = false) {
        guard watchedAccum > 5 else { return }
        HistoryStore.shared.record(item: item, seconds: watchedAccum, progress: duration > 0 ? time / duration : 0, finished: finished || (duration > 0 && time / duration > 0.9))
        watchedAccum = 0
    }

    // 控制
    func togglePlay() { engine.isPlaying ? engine.pause() : engine.play(); playing = engine.isPlaying }
    func seek(by d: Double) { let t = max(0, min(duration, engine.currentTime + d)); engine.seek(to: t); time = t }
    func seek(to t: Double) { engine.seek(to: t); time = t }
    func next() { guard let i = index, i + 1 < playlist.count else { return }; switchTo(playlist[i + 1]) }
    func prev() { guard let i = index, i > 0 else { return }; switchTo(playlist[i - 1]) }
    func switchTo(_ it: MediaItem) {
        flushHistory(); report()
        item = it; selectedMedia = nil; danmaku.load([], label: "")
        Task { await start(resume: true) }
    }
    func switchVersion(_ media: String) {
        let t = engine.currentTime
        selectedMedia = media
        Task {
            await start(resume: false)
            engine.seek(to: t)
        }
    }
    func markSkipOpeningHere() {
        skipOpening = Int(time)
        saveSkip(); toast = "片头设为 \(Self.fmt(time))"
    }
    func markSkipEndingHere() {
        skipEnding = Int(max(0, duration - time))
        saveSkip(); toast = "片尾设为倒数 \(Self.fmt(Double(skipEnding)))"
    }
    private func saveSkip() {
        let parent = playInfo["parent_guid"].string ?? item.parentGuid
        let o = skipOpening, e = skipEnding
        Task { try? await FnClient.shared.setSkip(parentGuid: parent, opening: o, ending: e) }
    }
    func close() {
        timer?.invalidate()
        report(); flushHistory()
        engine.stop()
    }

    static func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s); let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
