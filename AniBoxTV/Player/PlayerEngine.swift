import Foundation
import AVFoundation
import SwiftUI

/// 播放内核抽象：MPV（全格式、ASS 字幕、音轨切换）与系统 AVPlayer
protocol PlayerEngine: AnyObject {
    var currentTime: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    var isBuffering: Bool { get }
    var rate: Double { get set }
    func load(url: URL, headers: [String: String], start: Double)
    func play()
    func pause()
    func seek(to: Double)
    func stop()
    func setAudio(index: Int)          // 1-based track id, 0 = off
    func setSubtitle(index: Int)       // 1-based track id, 0 = off
    func addSubtitle(url: URL)
    var audioTracks: [(id: Int, title: String)] { get }
    var subtitleTracks: [(id: Int, title: String)] { get }
    func makeView() -> AnyView
}

final class AVEngine: PlayerEngine {
    let player = AVPlayer()
    var rate: Double = 1 { didSet { if isPlaying { player.rate = Float(rate) } } }
    var currentTime: Double { player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0 }
    var duration: Double { let d = player.currentItem?.duration.seconds ?? 0; return d.isFinite ? d : 0 }
    var isPlaying: Bool { player.timeControlStatus == .playing }
    var isBuffering: Bool { player.timeControlStatus == .waitingToPlayAtSpecifiedRate }

    func load(url: URL, headers: [String: String], start: Double) {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        if start > 0 { player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        player.play()
        player.rate = Float(rate)
    }
    func play() { player.play(); player.rate = Float(rate) }
    func pause() { player.pause() }
    func seek(to t: Double) { player.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
    func stop() { player.pause(); player.replaceCurrentItem(with: nil) }

    private func group(_ c: AVMediaCharacteristic) -> AVMediaSelectionGroup? {
        player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: c)
    }
    var audioTracks: [(id: Int, title: String)] {
        (group(.audible)?.options ?? []).enumerated().map { ($0.offset + 1, $0.element.displayName) }
    }
    var subtitleTracks: [(id: Int, title: String)] {
        (group(.legible)?.options ?? []).enumerated().map { ($0.offset + 1, $0.element.displayName) }
    }
    func setAudio(index: Int) {
        guard let g = group(.audible), index > 0, index <= g.options.count else { return }
        player.currentItem?.select(g.options[index - 1], in: g)
    }
    func setSubtitle(index: Int) {
        guard let g = group(.legible) else { return }
        player.currentItem?.select(index > 0 && index <= g.options.count ? g.options[index - 1] : nil, in: g)
    }
    func addSubtitle(url: URL) {}
    func makeView() -> AnyView { AnyView(AVLayerView(player: player)) }
}

struct AVLayerView: UIViewRepresentable {
    let player: AVPlayer
    final class V: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var pl: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> V { let v = V(); v.pl.player = player; v.pl.videoGravity = .resizeAspect; v.backgroundColor = .black; return v }
    func updateUIView(_ v: V, context: Context) { v.pl.player = player }
}
