/// Per-channel equivalents of the classic effect blend factors/equations.
/// Reference: local CrossUO GameEffect.cpp ApplyRenderMode.
public enum EffectBlend {
    public static func channel(source: UInt8, destination: UInt8, alpha: UInt8, mode: UInt32) -> UInt8 {
        guard alpha != 0 else { return destination }
        let s = Int(source), d = Int(destination), a = Int(alpha)
        let value: Int
        switch mode {
        case 1: value = d * s / 255
        case 2, 3: value = s + d
        case 4: value = (s * d + d * (255-a)) / 255
        case 5: value = 2 * s * d / 255
        case 6: value = (d * (255-s) - s * s) / 255
        default: value = (s * a + d * (255-a)) / 255
        }
        return UInt8(clamping: value)
    }
}
