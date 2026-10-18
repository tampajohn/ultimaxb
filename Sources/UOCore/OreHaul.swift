import Foundation

/// Confirmed drop/walk/pickup sequencing for one explicitly selected ore stack.
/// The adapter owns route planning, packet correlation and exclusive item moves.
public struct OreHaul {
    public enum StopReason:Equatable { case cancelled, disconnected, timeout, refused, oreChanged, positionChanged }
    public enum State:Equatable {
        case idle, waitingForDrop, waitingForWalk, waitingForPickup, completed
        case stopped(StopReason)
    }
    public enum Command:Equatable {
        case drop(serial:UInt32,amount:Int,at:WalkPoint)
        case walk(WalkPoint)
        case pickup(serial:UInt32,amount:Int,backpack:UInt32)
    }
    public enum Location:Equatable {
        case backpack(container:UInt32,amount:Int,graphic:Int,hue:Int)
        case ground(point:WalkPoint,amount:Int,graphic:Int,hue:Int)
        case unknown
    }
    public private(set) var state:State = .idle
    public private(set) var recoveryLocation:WalkPoint?
    private var ore:ContainerItem?
    private var path:[WalkPoint] = []
    private var step = 0
    private var dropPoint = WalkPoint(x:0,y:0,z:0)
    private var player = WalkPoint(x:0,y:0,z:0)
    private var acknowledged = false
    private var deadline:TimeInterval = 0
    public init() {}

    public mutating func start(ore:ContainerItem,player:WalkPoint,route:[WalkPoint],at time:TimeInterval)throws->Command {
        guard state == .idle,(0x19B7...0x19BA).contains(ore.graphic),
              ore.serial != 0,ore.serial != 0xFFFFFFFF,ore.container != 0,ore.container != 0xFFFFFFFF,
              (1...65535).contains(ore.amount),!route.isEmpty,route.count<=256,time.isFinite else {
            throw AssetError("Select an ore stack in your backpack and a reachable forge route.")
        }
        var previous = player
        for point in route {
            guard max(abs(point.x-previous.x),abs(point.y-previous.y)) == 1,
                  abs(point.z-previous.z)<=16,
                  (0..<65535).contains(point.x),(0..<65535).contains(point.y),(-128...127).contains(point.z) else {
                throw AssetError("Ore hauling requires adjacent reachable steps.")
            }
            previous = point
        }
        self.ore = ore; self.player = player; dropPoint = player; path = route
        state = .waitingForDrop; deadline = time+10
        return .drop(serial:ore.serial,amount:ore.amount,at:player)
    }
    /// Only route acknowledgements for this operation here. Legacy 0x29 carries
    /// no item identity, so overlapping manual transfers must stop the workflow.
    public mutating func acknowledgeTransfer() {
        if state == .waitingForDrop || state == .waitingForPickup { acknowledged = true }
    }
    public mutating func stop(_ reason:StopReason = .cancelled) {
        switch state {
        case .waitingForDrop,.waitingForWalk,.waitingForPickup: state = .stopped(reason)
        default: break
        }
    }
    /// location is looked up by the original selected serial. Never infer a merge
    /// or replacement serial from art/amount alone.
    public mutating func update(location:Location,player current:WalkPoint,movementSettled:Bool,at time:TimeInterval)->Command? {
        guard let ore else { return nil }
        switch state {
        case .waitingForDrop,.waitingForWalk,.waitingForPickup: break
        case .stopped:
            // A stop can race the drop result. Keep recovery information current
            // without issuing any further inventory or movement commands.
            if case .ground(let point,_,_,_) = location { recoveryLocation = point }
            if case .backpack(let container,let amount,let graphic,let hue) = location,
               container == ore.container,amount == ore.amount,graphic == ore.graphic,hue == ore.hue { recoveryLocation = nil }
            return nil
        default: return nil
        }
        if case .ground(let point,_,_,_) = location { recoveryLocation = point }
        guard time.isFinite,time<deadline else { stop(.timeout); return nil }
        switch location {
        case .backpack(let container,let amount,let graphic,let hue):
            guard container == ore.container,amount == ore.amount,graphic == ore.graphic,hue == ore.hue else {
                stop(.oreChanged); return nil
            }
        case .ground(_,let amount,let graphic,let hue):
            guard amount == ore.amount,graphic == ore.graphic,hue == ore.hue else { stop(.oreChanged); return nil }
        case .unknown: return nil // removal precedes destination updates
        }
        switch state {
        case .waitingForDrop:
            guard current == player else { stop(.positionChanged); return nil }
            guard case .ground(let point,_,_,_) = location else { return nil }
            guard point == player else { stop(.positionChanged); return nil }
            guard acknowledged,movementSettled else { return nil }
            acknowledged = false; state = .waitingForWalk; deadline = time+15
            return .walk(path[step])
        case .waitingForWalk:
            guard case .ground(let point,_,_,_) = location,point == player else { stop(.oreChanged); return nil }
            guard movementSettled else { return nil }
            if current == player { return nil }
            guard current == path[step] else { stop(.positionChanged); return nil }
            self.player = current
            state = .waitingForPickup; deadline = time+10
            return .pickup(serial:ore.serial,amount:ore.amount,backpack:ore.container)
        case .waitingForPickup:
            if case .ground(let point,_,_,_) = location,point != dropPoint { stop(.oreChanged); return nil }
            guard current == player else { stop(.positionChanged); return nil }
            guard acknowledged,case .backpack = location else { return nil }
            recoveryLocation = nil; acknowledged = false; step += 1
            if step == path.count { state = .completed; return nil }
            dropPoint = player
            state = .waitingForDrop; deadline = time+10
            return .drop(serial:ore.serial,amount:ore.amount,at:player)
        default: return nil
        }
    }
}
