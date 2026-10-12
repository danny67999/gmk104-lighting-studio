import Foundation
import CoreGraphics

enum KeySelectionTool: String, CaseIterable, Identifiable {
    case automatic = "Select keys", brush = "Drag across keys", rectangle = "Draw rectangle"
    var id: String { rawValue }
}

// All geometry is expressed in keyboard layout units, so hit testing remains
// consistent when the window is resized. Selection never sends keyboard data.
struct KeySelectionDrag {
    private enum Operation { case add, remove, replace, toggle }
    let tool: KeySelectionTool
    let start: CGPoint
    let initial: Set<String>
    let inset: CGFloat
    private let operation: Operation
    private var previous: CGPoint
    private(set) var current: CGPoint
    private var visited = Set<String>()
    private var moved = false

    init(tool: KeySelectionTool, start: CGPoint, initial: Set<String>, keys: [KeyGeometry],
         adding: Bool = false, removing: Bool = false, inset: CGFloat = 0.06) {
        self.start = start; self.previous = start; self.current = start
        self.initial = initial; self.inset = inset
        let first = keys.first { Self.bounds($0, inset: inset).contains(start) }?.id
        self.tool = tool == .automatic ? (first == nil ? .rectangle : .brush) : tool
        operation = removing ? .remove : adding ? .add : self.tool == .rectangle ? .replace :
            first.map { initial.contains($0) } == true ? .remove : .add
    }
    var rectangle: CGRect? {
        guard tool == .rectangle && moved else { return nil }
        return CGRect(x: min(start.x,current.x), y: min(start.y,current.y),
                      width: abs(start.x-current.x), height: abs(start.y-current.y))
    }
    static func bounds(_ key: KeyGeometry, inset: CGFloat) -> CGRect {
        CGRect(x: key.x, y: key.y, width: key.width, height: key.height).insetBy(dx: inset,dy: inset)
    }
    mutating func update(to point: CGPoint, keys: [KeyGeometry]) -> Set<String> {
        current = point
        moved = moved || hypot(point.x-start.x, point.y-start.y) >= 0.12
        let hit: Set<String>
        if tool == .rectangle, let rectangle {
            hit = Set(keys.filter {
                let overlap = rectangle.intersection(Self.bounds($0,inset: inset))
                return !overlap.isNull && overlap.width > 0 && overlap.height > 0
            }.map(\.id))
        } else {
            // Include keys between mouse samples so a quick brush cannot skip
            // keys, and remember visited keys so retracing never toggles twice.
            visited.formUnion(keys.filter {
                Self.intersects(from: previous,to: point,rect: Self.bounds($0,inset: inset))
            }.map(\.id))
            hit = visited
        }
        previous = point
        if tool == .rectangle && !moved && operation == .replace {
            return initial.symmetricDifference(hit)
        }
        switch operation {
        case .add: return initial.union(hit)
        case .remove: return initial.subtracting(hit)
        case .replace: return hit
        case .toggle: return initial.symmetricDifference(hit)
        }
    }
    private static func intersects(from a: CGPoint, to b: CGPoint, rect: CGRect) -> Bool {
        var lower: CGFloat = 0, upper: CGFloat = 1
        for (origin,delta,minimum,maximum) in [(a.x,b.x-a.x,rect.minX,rect.maxX),
                                             (a.y,b.y-a.y,rect.minY,rect.maxY)] {
            if abs(delta) < 0.000001 {
                if origin < minimum || origin > maximum { return false }
            } else {
                let first = (minimum-origin)/delta, last = (maximum-origin)/delta
                lower = max(lower,min(first,last)); upper = min(upper,max(first,last))
                if lower > upper { return false }
            }
        }
        return true
    }
}
