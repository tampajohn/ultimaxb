import AppKit
import AVFoundation
import UOCore

@MainActor
final class GameAudio {
    private let settings = UserDefaults(suiteName:"com.ultimaxb.UltimaMac")!
    private var voices:[AVAudioPlayer] = []
    var enabled:Bool {
        get { settings.object(forKey:"soundEffectsEnabled") == nil || settings.bool(forKey:"soundEffectsEnabled") }
        set { settings.set(newValue,forKey:"soundEffectsEnabled"); if !newValue { voices.forEach { $0.stop() }; voices.removeAll() } }
    }
    private var music:AVAudioPlayer?
    private var midi:AVMIDIPlayer?
    private var musicID:Int?
    var musicEnabled:Bool {
        get { settings.object(forKey:"musicEnabled") == nil || settings.bool(forKey:"musicEnabled") }
        set {
            settings.set(newValue,forKey:"musicEnabled")
            if newValue { resume() } else { music?.pause(); midi?.stop() }
        }
    }
    func pause() { voices.forEach { $0.stop() }; voices.removeAll(); music?.pause(); midi?.stop() }
    func resume() {
        guard musicEnabled, NSApplication.shared.isActive else { return }
        if let music, !music.isPlaying {
            let started = music.play()
            Telemetry.shared.record("music_playback",["id":musicID as Any? ?? NSNull(),"started":started,"volume":music.volume])
        }
        if let id = musicID { playMIDI(id) }
    }
    func stop() { pause(); music = nil; midi = nil; musicID = nil }
    private func playMIDI(_ id:Int) {
        guard musicID == id, musicEnabled, NSApplication.shared.isActive, let midi, !midi.isPlaying else { return }
        midi.play { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.musicID == id, MusicCatalog.track(id)?.loops == true else { return }
                self.midi?.currentPosition = 0; self.playMIDI(id)
            }
        }
    }
    func playMusic(_ id:Int, directory:URL) {
        if id == 0xFFFF { music?.stop(); midi?.stop(); music = nil; midi = nil; musicID = nil; return }
        guard let track = MusicCatalog.track(id) else {
            Telemetry.shared.record("music_unknown_track",["id":id]); return
        }
        if musicID == id { return }
        music?.stop(); midi?.stop(); music = nil; midi = nil; musicID = nil
        do {
            let files = try FileManager.default.contentsOfDirectory(at:directory.appendingPathComponent("MUSIC"),includingPropertiesForKeys:nil)
            if let url = files.first(where: { $0.lastPathComponent.lowercased() == track.name+".mp3" }) {
                let player = try AVAudioPlayer(contentsOf:url)
                player.volume = 0.3; player.numberOfLoops = track.loops ? -1 : 0
                music = player; musicID = id
            } else if let url = files.first(where: { $0.lastPathComponent.lowercased() == track.name+".mid" }) {
                midi = try AVMIDIPlayer(contentsOf:url,soundBankURL:nil); midi?.prepareToPlay(); musicID = id
            } else { Telemetry.shared.record("music_asset_missing",["id":id]); return }
            resume()
            Telemetry.shared.record("music_loaded",["id":id,"loops":track.loops,"enabled":musicEnabled])
        } catch { Telemetry.shared.record("music_load_failed",["id":id]) }
    }
    func play(_ sound:SoundEffect,assets:ClientAssets,listener:WorldMobile?) {
        guard sound.hasSample, enabled, NSApplication.shared.isActive, let listener else { return }
        let gain = sound.gain(listenerX:listener.x,listenerY:listener.y)
        guard gain>0 else { return }
        do {
            guard let wave = try assets.sounds?.wave(sound.id) else {
                Telemetry.shared.record("sound_asset_missing",["id":sound.id]); return
            }
            voices.removeAll { !$0.isPlaying }
            if voices.count >= 12 { voices.removeFirst().stop() }
            let voice = try AVAudioPlayer(data:wave)
            voice.volume = 0.55*gain
            voice.pan = sound.pan(listenerX:listener.x,listenerY:listener.y)
            voice.numberOfLoops = 0
            if voice.play() {
                voices.append(voice)
                Telemetry.shared.record("sound_played",["id":sound.id,"voices":voices.count,"cache_bytes":assets.sounds?.cacheBytes ?? 0])
            } else { Telemetry.shared.record("sound_play_failed",["id":sound.id]) }
        } catch { Telemetry.shared.record("sound_decode_failed",["id":sound.id]) }
    }
}
