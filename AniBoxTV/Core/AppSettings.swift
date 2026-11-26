import Foundation
import SwiftUI

enum PlayerEngineKind: String, CaseIterable, Identifiable {
    case mpv, avplayer
    var id: String { rawValue }
    var title: String { self == .mpv ? "MPV（全格式）" : "系统 AVPlayer" }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // 播放
    @AppStorage("engine") var engine: PlayerEngineKind = .mpv
    @AppStorage("autoSkipOpening") var autoSkipOpening = true
    @AppStorage("autoSkipEnding") var autoSkipEnding = true
    @AppStorage("autoNextEpisode") var autoNextEpisode = true
    @AppStorage("defaultSpeed") var defaultSpeed = 1.0
    @AppStorage("seekStep") var seekStep = 10.0
    @AppStorage("preferSubLang") var preferSubLang = "chi,zho,zh,chs"
    @AppStorage("preferAudioLang") var preferAudioLang = "jpn,ja"
    @AppStorage("subScale") var subScale = 1.0
    @AppStorage("hdrPassthrough") var hdrPassthrough = true

    // 弹幕
    @AppStorage("danmakuEnabled") var danmakuEnabled = true
    @AppStorage("danmakuServers") var danmakuServers = ""   // 多个地址用换行分隔，含 TOKEN 路径
    @AppStorage("danmakuOpacity") var danmakuOpacity = 0.85
    @AppStorage("danmakuFontSize") var danmakuFontSize = 38.0
    @AppStorage("danmakuSpeed") var danmakuSpeed = 1.0
    @AppStorage("danmakuArea") var danmakuArea = 0.5
    @AppStorage("danmakuShowTop") var danmakuShowTop = true
    @AppStorage("danmakuShowBottom") var danmakuShowBottom = true
    @AppStorage("danmakuBlockWords") var danmakuBlockWords = ""
    @AppStorage("danmakuMaxPerSecond") var danmakuMaxPerSecond = 30.0

    // 元数据
    @AppStorage("tmdbKey") var tmdbKey = ""
    @AppStorage("tmdbBase") var tmdbBase = "https://api.themoviedb.org/3"
    @AppStorage("tmdbImageBase") var tmdbImageBase = "https://image.tmdb.org/t/p"
    @AppStorage("bgmBase") var bgmBase = "https://api.bgm.tv"
    @AppStorage("bgmToken") var bgmToken = ""
    @AppStorage("useBangumi") var useBangumi = true
    @AppStorage("useAniList") var useAniList = true
    @AppStorage("useTMDB") var useTMDB = true

    // 界面
    @AppStorage("detailStyle") var detailStyle = "hero"   // hero / editorial
    @AppStorage("showCarousel") var showCarousel = true
    @AppStorage("posterCornerRadius") var posterCornerRadius = 18.0
    @AppStorage("hideWatched") var hideWatched = false
    @AppStorage("iptvURL") var iptvURL = ""

    // 高级
    @AppStorage("authxKey") var authxKey = ""
    @AppStorage("authxSecret") var authxSecret = ""
}
