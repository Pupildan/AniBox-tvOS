import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var s: AppSettings
    @EnvironmentObject var session: Session
    @State private var cacheCleared = false
    var body: some View {
        ZStack {
            AppBackground()
            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("设置").font(.system(size: 56, weight: .heavy))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(session.username).font(.title2)
                        Text(session.server).foregroundStyle(.secondary)
                    }
                    .padding(30).glass(26)
                    Button("退出登录", role: .destructive) { session.logout() }.buttonStyle(GlassButtonStyle())
                    Text("AniBox tvOS 0.1 · 基于 FNOSP/AniBox（AGPL-3.0）").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(width: 520)
                Form {
                    Section("播放") {
                        if EngineFactory.mpvAvailable {
                            Picker("播放内核", selection: $s.engine) { ForEach(PlayerEngineKind.allCases) { Text($0.title).tag($0) } }
                        } else {
                            Text("播放内核：系统 AVPlayer（本构建未集成 MPVKit）")
                        }
                        Toggle("自动跳过片头", isOn: $s.autoSkipOpening)
                        Toggle("自动跳过片尾", isOn: $s.autoSkipEnding)
                        Toggle("自动播放下一集", isOn: $s.autoNextEpisode)
                        Picker("默认倍速", selection: $s.defaultSpeed) { ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { Text(String(format: "%.2gx", $0)).tag($0) } }
                        Picker("快进/快退步长", selection: $s.seekStep) { ForEach([5.0, 10.0, 15.0, 30.0], id: \.self) { Text("\(Int($0)) 秒").tag($0) } }
                        TextField("首选字幕语言", text: $s.preferSubLang)
                        TextField("首选音轨语言", text: $s.preferAudioLang)
                        Toggle("HDR / 杜比视界直通", isOn: $s.hdrPassthrough)
                    }
                    Section("弹幕") {
                        Toggle("启用弹幕", isOn: $s.danmakuEnabled)
                        TextField("弹幕源地址（danmu_api，多个用逗号分隔，含 TOKEN 路径）", text: $s.danmakuServers)
                        Picker("透明度", selection: $s.danmakuOpacity) { ForEach([0.4, 0.6, 0.85, 1.0], id: \.self) { Text("\(Int($0 * 100))%").tag($0) } }
                        Picker("字号", selection: $s.danmakuFontSize) { ForEach([28.0, 34.0, 38.0, 46.0, 56.0], id: \.self) { Text("\(Int($0))").tag($0) } }
                        Picker("速度", selection: $s.danmakuSpeed) { ForEach([0.5, 0.75, 1.0, 1.5, 2.0], id: \.self) { Text(String(format: "%.2gx", $0)).tag($0) } }
                        Picker("显示区域", selection: $s.danmakuArea) { ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { Text("\(Int($0 * 100))%").tag($0) } }
                        Toggle("显示顶部弹幕", isOn: $s.danmakuShowTop)
                        Toggle("显示底部弹幕", isOn: $s.danmakuShowBottom)
                        TextField("屏蔽词（逗号分隔）", text: Binding(get: { s.danmakuBlockWords.replacingOccurrences(of: "\n", with: ",") },
                                                                set: { s.danmakuBlockWords = $0.replacingOccurrences(of: ",", with: "\n") }))
                    }
                    Section("元数据") {
                        Toggle("Bangumi", isOn: $s.useBangumi)
                        Toggle("TMDB", isOn: $s.useTMDB)
                        Toggle("AniList", isOn: $s.useAniList)
                        TextField("TMDB API Key（v3 key 或 v4 Token）", text: $s.tmdbKey)
                        TextField("TMDB API 地址（可填镜像）", text: $s.tmdbBase)
                        TextField("TMDB 图片地址", text: $s.tmdbImageBase)
                        TextField("Bangumi API 地址（可填镜像）", text: $s.bgmBase)
                        TextField("Bangumi Access Token（同步收藏/进度）", text: $s.bgmToken)
                    }
                    Section("界面") {
                        Toggle("首页轮播", isOn: $s.showCarousel)
                        Picker("详情页版式", selection: $s.detailStyle) { Text("沉浸大图").tag("hero"); Text("杂志双栏").tag("editorial") }
                        Toggle("首页隐藏已看", isOn: $s.hideWatched)
                        Picker("海报圆角", selection: $s.posterCornerRadius) { ForEach([8.0, 18.0, 28.0], id: \.self) { Text("\(Int($0))").tag($0) } }
                    }
                    Section("直播") {
                        TextField("IPTV 订阅地址（M3U / TXT）", text: $s.iptvURL)
                    }
                    Section("高级") {
                        TextField("Authx Key（留空使用内置）", text: $s.authxKey)
                        TextField("Authx Secret（留空使用内置）", text: $s.authxSecret)
                        Button(cacheCleared ? "已清除缓存" : "清除图片与元数据缓存") {
                            let c = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                            try? FileManager.default.removeItem(at: c.appendingPathComponent("img"))
                            try? FileManager.default.removeItem(at: c.appendingPathComponent("meta"))
                            URLCache.shared.removeAllCachedResponses()
                            cacheCleared = true
                        }
                    }
                    Section("关于") {
                        Text("本项目为 AniBox（github.com/FNOSP/AniBox）的 tvOS 移植版，遵循 AGPL-3.0 开源。非飞牛官方出品，与飞牛官方无关联。")
                    }
                }
            }
            .padding(80)
        }
    }
}
