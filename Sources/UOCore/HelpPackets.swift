import Foundation

public enum HelpPackets {
    /// Legacy assistance request: opcode, help type, 256-byte empty text field.
    /// The server decides which help/stuck menu to show; this selects no option.
    public static let request = Data([0x9B]) + Data(repeating:0,count:257)
}
