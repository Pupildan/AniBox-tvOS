import Foundation
import SwiftUI
import UIKit
#if canImport(Libmpv)
import Libmpv

/// MPV 内核（MPVKit）：vo=gpu-next + Metal 层渲染，支持全部容器/编码、ASS 字幕、外挂字幕、音轨切换
final class MPVEngine: PlayerEngine {
    private var mpv: OpaquePointer?
    private let metalView = MPVMetalView()
    private let queue = DispatchQueue(label: "mpv", qos: .userInitiated)
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    var rate: Double = 1 { didSet { setProp("speed", String(rate)) } }
    private var tracks: [(type: String, id: Int, title: String)] = []

    init() {
        mpv = mpv_create()
        guard let mpv else { return }
        var layer = metalView.metalLayer
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layer)
        opt("vo", "gpu-next")
        opt("gpu-api", "vulkan")
        opt("hwdec", "videotoolbox")
        opt("video-rotate", "no")
        opt("subs-match-os-language", "yes")
        opt("subs-fallback", "yes")
        opt("slang", AppSettings.shared.preferSubLang)
        opt("alang", AppSettings.shared.preferAudioLang)
        opt("sub-scale", String(AppSettings.shared.subScale))
        opt("cache", "yes")
        opt("demuxer-max-bytes", "150MiB")
        opt("demuxer-readahead-secs", "20")
        opt("tls-verify", "no")
        if AppSettings.shared.hdrPassthrough { opt("target-colorspace-hint", "yes") }
        mpv_initialize(mpv)
        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "track-list/count", MPV_FORMAT_INT64)
        mpv_set_wakeup_callback(mpv, { ctx in
            let me = Unmanaged<MPVEngine>.fromOpaque(ctx!).takeUnretainedValue()
            me.queue.async { me.drain() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    deinit { if let mpv { mpv_terminate_destroy(mpv) } }

    private func opt(_ k: String, _ v: String) { if let mpv { mpv_set_option_string(mpv, k, v) } }
    private func setProp(_ k: String, _ v: String) { if let mpv { mpv_set_property_string(mpv, k, v) } }
    private func command(_ args: [String]) {
        guard let mpv else { return }
        var cargs = args.map { strdup($0) } + [nil]
        cargs.withUnsafeMutableBufferPointer { p in
            p.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: p.count) { _ = mpv_command(mpv, $0) }
        }
        for c in cargs { free(c) }
    }
    private func getString(_ k: String) -> String? {
        guard let mpv, let c = mpv_get_property_string(mpv, k) else { return nil }
        defer { mpv_free(c) }
        return String(cString: c)
    }

    private func drain() {
        guard let mpv else { return }
        while true {
            guard let ev = mpv_wait_event(mpv, 0) else { break }
            if ev.pointee.event_id == MPV_EVENT_NONE { break }
            if ev.pointee.event_id == MPV_EVENT_PROPERTY_CHANGE, let pp = ev.pointee.data?.assumingMemoryBound(to: mpv_event_property.self) {
                let p = pp.pointee
                let name = String(cString: p.name)
                switch (name, p.format) {
                case ("time-pos", MPV_FORMAT_DOUBLE): currentTime = p.data.assumingMemoryBound(to: Double.self).pointee
                case ("duration", MPV_FORMAT_DOUBLE): duration = p.data.assumingMemoryBound(to: Double.self).pointee
                case ("pause", MPV_FORMAT_FLAG): isPlaying = p.data.assumingMemoryBound(to: Int32.self).pointee == 0
                case ("paused-for-cache", MPV_FORMAT_FLAG): isBuffering = p.data.assumingMemoryBound(to: Int32.self).pointee != 0
                case ("track-list/count", _): refreshTracks()
                default: break
                }
            }
        }
    }
    private func refreshTracks() {
        let n = Int(getString("track-list/count") ?? "0") ?? 0
        var t: [(String, Int, String)] = []
        for i in 0..<n {
            let type = getString("track-list/\(i)/type") ?? ""
            let id = Int(getString("track-list/\(i)/id") ?? "0") ?? 0
            let title = getString("track-list/\(i)/title") ?? ""
            let lang = getString("track-list/\(i)/lang") ?? ""
            let codec = getString("track-list/\(i)/codec") ?? ""
            t.append((type, id, [title, lang, codec].filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        tracks = t
    }

    func load(url: URL, headers: [String: String], start: Double) {
        let h = headers.map { "\($0.key): \($0.value)" }.joined(separator: ",")
        setProp("http-header-fields", h)
        if start > 0 { setProp("start", String(Int(start))) } else { setProp("start", "none") }
        setProp("speed", String(rate))
        command(["loadfile", url.absoluteString, "replace"])
        setProp("pause", "no")
    }
    func play() { setProp("pause", "no") }
    func pause() { setProp("pause", "yes") }
    func seek(to t: Double) { command(["seek", String(max(0, t)), "absolute+exact"]) }
    func stop() { command(["stop"]) }
    func setAudio(index: Int) { setProp("aid", index == 0 ? "no" : String(index)) }
    func setSubtitle(index: Int) { setProp("sid", index == 0 ? "no" : String(index)) }
    func addSubtitle(url: URL) { command(["sub-add", url.absoluteString, "select"]) }
    var audioTracks: [(id: Int, title: String)] { tracks.filter { $0.type == "audio" }.map { ($0.id, $0.title.isEmpty ? "音轨 \($0.id)" : $0.title) } }
    var subtitleTracks: [(id: Int, title: String)] { tracks.filter { $0.type == "sub" }.map { ($0.id, $0.title.isEmpty ? "字幕 \($0.id)" : $0.title) } }
    func makeView() -> AnyView { AnyView(MPVViewRep(view: metalView)) }
}

final class MPVMetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.drawableSize = CGSize(width: bounds.width * contentScaleFactor, height: bounds.height * contentScaleFactor)
    }
}
struct MPVViewRep: UIViewRepresentable {
    let view: MPVMetalView
    func makeUIView(context: Context) -> MPVMetalView { view }
    func updateUIView(_ uiView: MPVMetalView, context: Context) {}
}
#endif

enum EngineFactory {
    static var mpvAvailable: Bool {
        #if canImport(Libmpv)
        return true
        #else
        return false
        #endif
    }
    static func make() -> PlayerEngine {
        #if canImport(Libmpv)
        if AppSettings.shared.engine == .mpv { return MPVEngine() }
        #endif
        return AVEngine()
    }
}
