import Foundation
import AVFoundation
import UOCore
@main struct Check {
 static func main() throws {
  let directory = URL(fileURLWithPath:"uo1998-client/MUSIC")
  let files = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
  var decoded = 0, midiOnly = 0
  for track in MusicCatalog.tracks {
   if let url = files.first(where: { $0.lastPathComponent.lowercased() == track.name+".mp3" }) {
    let player = try AVAudioPlayer(contentsOf:url)
    precondition(player.duration > 0); decoded += 1
   } else if files.contains(where: { $0.lastPathComponent.lowercased() == track.name+".mid" }) { midiOnly += 1 }
   else { throw NSError(domain:"Missing music",code:1) }
  }
  print("Music IDs: \(decoded) MP3 tracks decoded without playback; \(midiOnly) MIDI-only tracks present.")
 }
}
