import SwiftUI
import GameController

/// 全屏播放器：针对 Siri Remote 优化
/// - 触控板点按 / 播放键：暂停/继续
/// - 左右方向（触控板边缘点按/滑动）：快退/快进（可在设置调整步长），长按连续拖动
/// - 上：呼出控制条；下：呼出面板（字幕/音轨/弹幕/倍速/版本/片头片尾）
/// - 菜单键：先收起面板，再退出播放
struct PlayerView: View {
    @StateObject private var m: PlayerModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    @State private var panel: Panel?
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing: Double?
    @FocusState private var focus: Bool

    enum Panel: String, CaseIterable, Identifiable { case subtitle = "字幕", audio = "音轨", danmaku = "弹幕", speed = "倍速", version = "版本", skip = "片头片尾", episodes = "选集"; var id: String { rawValue } }

    init(item: MediaItem, playlist: [MediaItem]) {
        let model = PlayerModel(item: item, playlist: playlist)
        if let v = UserDefaults.standard.string(forKey: "ver.\(item.guid)") { model.selectedMedia = v; UserDefaults.standard.removeObject(forKey: "ver.\(item.guid)") }
        _m = StateObject(wrappedValue: model)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            m.engine.makeView().ignoresSafeArea()
            if settings.danmakuEnabled {
                DanmakuOverlay(engine: m.danmaku, currentTime: { m.engine.currentTime }, isPlaying: { m.engine.isPlaying })
                    .ignoresSafeArea()
            }
            if m.loading || m.buffering { ProgressView().scaleEffect(2) }
            if let e = m.error { ErrorView(message: e) { Task { await m.start() } } }
            if showControls && panel == nil { controls.transition(.opacity) }
            if let panel { panelView(panel).transition(.move(edge: .bottom).combined(with: .opacity)) }
            if let t = m.toast {
                Text(t).font(.system(size: 26, weight: .semibold)).padding(.horizontal, 30).padding(.vertical, 16).glass(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(60)
                    .task(id: t) { try? await Task.sleep(nanoseconds: 2_500_000_000); m.toast = nil }
            }
            skipButton
        }
        .focusable(panel == nil)
        .focused($focus)
        .onAppear { focus = true; Task { await m.start() }; bump() }
        .onDisappear { m.close() }
        .onPlayPauseCommand { m.togglePlay(); bump() }
        .onMoveCommand { dir in handleMove(dir) }
        .onExitCommand {
            if panel != nil { withAnimation { panel = nil }; focus = true }
            else if showControls && scrubbing == nil && m.playing { withAnimation { showControls = false } }
            else { m.close(); dismiss() }
        }
        .onTapGesture { if panel == nil { if let s = scrubbing { m.seek(to: s); scrubbing = nil } else { m.togglePlay() }; bump() } }
        .onLongPressGesture(minimumDuration: 0.6) { withAnimation { panel = .subtitle } }
        .animation(.easeInOut(duration: 0.25), value: showControls)
        .animation(.spring(response: 0.35), value: panel)
    }

    func handleMove(_ dir: MoveCommandDirection) {
        guard panel == nil else { return }
        switch dir {
        case .left: if showControls, scrubbing != nil { scrubbing = max(0, (scrubbing ?? m.time) - settings.seekStep * 3) } else { m.seek(by: -settings.seekStep); m.danmaku.reset() }
        case .right: if showControls, scrubbing != nil { scrubbing = min(m.duration, (scrubbing ?? m.time) + settings.seekStep * 3) } else { m.seek(by: settings.seekStep); m.danmaku.reset() }
        case .up: if showControls { scrubbing = scrubbing == nil ? m.time : nil } 
        case .down: withAnimation { panel = .subtitle }
        @unknown default: break
        }
        bump()
    }
    func bump() {
        withAnimation { showControls = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled && m.playing && scrubbing == nil && panel == nil { withAnimation { showControls = false } }
        }
    }

    // MARK: 控制条
    var controls: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.title).font(.system(size: 44, weight: .bold))
                    Text(m.subtitle).font(.system(size: 26)).foregroundStyle(.secondary)
                    if !m.danmaku.label.isEmpty { Label(m.danmaku.label, systemImage: "text.bubble").font(.system(size: 20)).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(Date.now, style: .time).font(.system(size: 30, weight: .semibold)).padding(.horizontal, 22).padding(.vertical, 10).glass(18)
            }
            .padding(60)
            .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
            Spacer()
            VStack(spacing: 22) {
                HStack(spacing: 30) {
                    Image(systemName: m.playing ? "pause.fill" : "play.fill").font(.system(size: 34))
                    Text(PlayerModel.fmt(scrubbing ?? m.time)).monospacedDigit()
                    GeometryReader { g in
                        let p = m.duration > 0 ? (scrubbing ?? m.time) / m.duration : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.22))
                            Capsule().fill(.white).frame(width: g.size.width * p)
                            if m.skipOpening > 0, m.duration > 0 { Rectangle().fill(.yellow).frame(width: 3).offset(x: g.size.width * Double(m.skipOpening) / m.duration) }
                            if m.skipEnding > 0, m.duration > 0 { Rectangle().fill(.yellow).frame(width: 3).offset(x: g.size.width * (m.duration - Double(m.skipEnding)) / m.duration) }
                            if scrubbing != nil { Circle().fill(.white).frame(width: 30, height: 30).offset(x: g.size.width * p - 15) }
                        }
                    }
                    .frame(height: scrubbing != nil ? 14 : 8)
                    Text("-" + PlayerModel.fmt(max(0, m.duration - (scrubbing ?? m.time)))).monospacedDigit()
                }
                .font(.system(size: 26, weight: .semibold))
                HStack(spacing: 34) {
                    hint("arrow.left.arrow.right", "左右 ±\(Int(settings.seekStep))秒")
                    hint("arrow.up", scrubbing == nil ? "上 拖动进度" : "点按确认跳转")
                    hint("arrow.down", "下 字幕/音轨/弹幕")
                    hint("playpause", "播放/暂停")
                    if m.hasNext { hint("forward.end", "面板中切换下一集") }
                    if m.speed != 1 { Text(String(format: "%.2gx", m.speed)).font(.system(size: 22, weight: .bold)) }
                }
                .font(.system(size: 20)).foregroundStyle(.secondary)
            }
            .padding(40).glass(36).padding(.horizontal, 60).padding(.bottom, 50)
        }
    }
    func hint(_ icon: String, _ t: String) -> some View { Label(t, systemImage: icon) }

    // 片头/片尾跳过按钮
    @ViewBuilder var skipButton: some View {
        if !settings.autoSkipOpening, m.skipOpening > 0, m.time > 1, m.time < Double(m.skipOpening) {
            Text("下滑 → 片头片尾 可跳过片头").padding(20).glass(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(80)
        } else if m.hasNext, m.skipEnding > 0, m.duration > 0, m.time > m.duration - Double(m.skipEnding), !settings.autoSkipEnding {
            Text("即将播放下一集").padding(20).glass(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(80)
        }
    }

    // MARK: 面板
    func panelView(_ p: Panel) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                ForEach(Panel.allCases) { x in
                    if x != .version || m.versions.count > 1, x != .episodes || !m.playlist.isEmpty {
                        Chip(text: x.rawValue, selected: x == p) { panel = x }
                    }
                }
            }
            .focusSection()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) { panelContent(p) }.padding(.vertical, 24).padding(.horizontal, 8)
            }
            .scrollClipDisabled()
            .focusSection()
        }
        .padding(40).glass(40).padding(50)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder func panelContent(_ p: Panel) -> some View {
        switch p {
        case .subtitle:
            opt("关闭字幕") { m.engine.setSubtitle(index: 0) }
            ForEach(m.engine.subtitleTracks, id: \.id) { t in opt(t.title) { m.engine.setSubtitle(index: t.id); m.toast = "字幕：\(t.title)" } }
            ForEach(m.nasSubtitles.filter { $0["is_external"].bool }, id: \.self) { s in
                opt("外挂 · " + (s["title"].string ?? s["language"].str)) {
                    Task {
                        if let u = FnClient.shared.subtitleURL(s["guid"].str), let d = try? await FnClient.shared.download(u) {
                            let f = FileManager.default.temporaryDirectory.appendingPathComponent("\(s["guid"].str).\(s["format"].string ?? "srt")")
                            try? d.write(to: f); m.engine.addSubtitle(url: f)
                        }
                    }
                }
            }
            opt("字幕放大") { settings.subScale = min(2.5, settings.subScale + 0.1); m.toast = String(format: "字幕缩放 %.1f（重新起播生效）", settings.subScale) }
            opt("字幕缩小") { settings.subScale = max(0.5, settings.subScale - 0.1); m.toast = String(format: "字幕缩放 %.1f（重新起播生效）", settings.subScale) }
        case .audio:
            ForEach(m.engine.audioTracks, id: \.id) { t in opt(t.title) { m.engine.setAudio(index: t.id); m.toast = "音轨：\(t.title)" } }
            if m.engine.audioTracks.isEmpty { Text("无可选音轨").foregroundStyle(.secondary) }
        case .danmaku:
            opt(settings.danmakuEnabled ? "关闭弹幕" : "开启弹幕") { settings.danmakuEnabled.toggle() }
            opt("重新匹配") { Task { await m.loadDanmaku() } }
            opt("弹幕提前 1 秒") { m.danmaku.offset += 1; m.danmaku.reset() }
            opt("弹幕延后 1 秒") { m.danmaku.offset -= 1; m.danmaku.reset() }
            opt("透明度 \(Int(settings.danmakuOpacity * 100))%") { settings.danmakuOpacity = settings.danmakuOpacity <= 0.3 ? 1 : settings.danmakuOpacity - 0.15 }
            opt("字号 \(Int(settings.danmakuFontSize))") { settings.danmakuFontSize = settings.danmakuFontSize >= 56 ? 28 : settings.danmakuFontSize + 6 }
            opt("速度 \(String(format: "%.1f", settings.danmakuSpeed))x") { settings.danmakuSpeed = settings.danmakuSpeed >= 2 ? 0.5 : settings.danmakuSpeed + 0.25 }
            opt("显示区域 \(Int(settings.danmakuArea * 100))%") { settings.danmakuArea = settings.danmakuArea >= 1 ? 0.25 : settings.danmakuArea + 0.25 }
            opt(settings.danmakuShowTop ? "隐藏顶部弹幕" : "显示顶部弹幕") { settings.danmakuShowTop.toggle() }
            opt(settings.danmakuShowBottom ? "隐藏底部弹幕" : "显示底部弹幕") { settings.danmakuShowBottom.toggle() }
            Text("共 \(m.danmaku.items.count) 条").foregroundStyle(.secondary)
        case .speed:
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { s in
                opt(String(format: "%.2gx", s), selected: m.speed == s) { m.speed = s; m.toast = String(format: "倍速 %.2gx", s) }
            }
        case .version:
            ForEach(m.versions, id: \.self) { v in
                let title = [v["resolution_type"].str, v["codec_name"].str.uppercased(), v["color_range_type"].str].filter { !$0.isEmpty }.joined(separator: " ")
                opt(title.isEmpty ? v["title"].str : title, selected: v["media_guid"].str == m.selectedMedia) { m.switchVersion(v["media_guid"].str); panel = nil }
            }
        case .skip:
            opt("把当前位置设为片头结束") { m.markSkipOpeningHere() }
            opt("把当前位置设为片尾开始") { m.markSkipEndingHere() }
            opt("跳过片头 → \(PlayerModel.fmt(Double(m.skipOpening)))") { m.seek(to: Double(m.skipOpening)) }
            opt(settings.autoSkipOpening ? "自动跳片头：开" : "自动跳片头：关") { settings.autoSkipOpening.toggle() }
            opt(settings.autoSkipEnding ? "自动跳片尾：开" : "自动跳片尾：关") { settings.autoSkipEnding.toggle() }
            opt("清除片头片尾") { m.skipOpening = 0; m.skipEnding = 0; Task { try? await FnClient.shared.setSkip(parentGuid: m.item.parentGuid, opening: 0, ending: 0) } }
        case .episodes:
            if m.hasPrev { opt("上一集") { m.prev(); panel = nil } }
            if m.hasNext { opt("下一集") { m.next(); panel = nil } }
            ForEach(m.playlist) { e in
                opt("\(e.episode > 0 ? "\(e.episode). " : "")\(e.title)", selected: e.guid == m.item.guid) { m.switchTo(e); panel = nil }
            }
        }
    }
    func opt(_ t: String, selected: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(t, action: a).buttonStyle(GlassButtonStyle(radius: 22, prominent: selected))
    }
}
