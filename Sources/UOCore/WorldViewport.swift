import Foundation

/// Keep the classic vertical field of view while revealing terrain to either side.
/// Extreme aspect ratios reduce raster resolution to stay within the renderer budget.
public struct WorldViewport: Equatable, Sendable {
    public let width:Int
    public let height:Int
    public init(availableWidth:Double,availableHeight:Double) {
        let aspect=max(1,availableWidth)/max(1,availableHeight)
        let desiredWidth=720*aspect
        width=max(1,min(2048,Int(desiredWidth.rounded())))
        height=max(1,min(720,Int((Double(width)/aspect).rounded())))
    }
}
