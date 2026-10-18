import Foundation
import AVFoundation
import UOCore
@main struct Check {
 static func main() throws {
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let sounds = assets.sounds!
  var validated = 0
  for id in 0..<2048 {
   guard let wave = try sounds.wave(id) else { continue }
   if validated < 12 {
    let player = try AVAudioPlayer(data:wave)
    precondition(player.duration>0 && player.numberOfChannels == 1)
    precondition(abs(player.format.sampleRate-22050)<1)
   }
   validated += 1
   precondition(sounds.cacheBytes<=sounds.cacheLimit)
  }
  precondition(validated>100)
  print("Decoded \(validated) original sounds; AVFoundation accepted 12 mono 22050 Hz samples; cache \(sounds.cacheBytes) bytes within \(sounds.cacheLimit)")
 }
}
