import Foundation

/// Explore incoming movement edges, not reversed outgoing moves. Exhaustion
/// proves no walking route from the source within the supplied static graph.
/// A budget limit is inconclusive and must never be reported as disconnection.
public enum ReverseWalkSearch {
    public struct Result {
        public let route:[WalkPoint]?
        public let statistics:WalkPath.SearchStatistics
    }
    public static func find(from start:WalkPoint,goals:[WalkPoint],limit:Int,
                            predecessors:(WalkPoint)throws->[WalkPoint]) rethrows -> Result {
        var queue=Array(Set(goals)).sorted { ($0.x,$0.y,$0.z)<($1.x,$1.y,$1.z) }
        var seen=Set(queue),towardGoal:[WalkPoint:WalkPoint]=[:],head=0
        while head<queue.count {
            let current=queue[head]
            if current==start {
                var route:[WalkPoint]=[],point=start
                while let next=towardGoal[point] { route.append(next); point=next }
                return Result(route:route,statistics:.init(outcome:.found,expanded:head,popped:head+1))
            }
            guard head<max(0,limit) else {
                return Result(route:nil,statistics:.init(outcome:.budgetExceeded,expanded:head,popped:head))
            }
            head += 1
            for previous in try predecessors(current) where seen.insert(previous).inserted {
                towardGoal[previous]=current; queue.append(previous)
            }
        }
        return Result(route:nil,statistics:.init(outcome:.exhausted,expanded:head,popped:head))
    }
}
