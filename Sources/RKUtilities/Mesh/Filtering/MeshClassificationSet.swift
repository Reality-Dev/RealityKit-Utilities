import ARKit
import RealityKit

@preconcurrency
public struct MeshClassificationSet: OptionSet, Sendable, MeshClassification {
    public let rawValue: Int
    
    // Architecture
    public static let ceiling       = MeshClassificationSet(rawValue: 1 << 0)
    public static let door          = MeshClassificationSet(rawValue: 1 << 1)
    public static let floor         = MeshClassificationSet(rawValue: 1 << 2)
    public static let stairs        = MeshClassificationSet(rawValue: 1 << 3)
    public static let wall          = MeshClassificationSet(rawValue: 1 << 4)
    public static let window        = MeshClassificationSet(rawValue: 1 << 5)
    
    // Furniture
    public static let bed           = MeshClassificationSet(rawValue: 1 << 6)
    public static let cabinet       = MeshClassificationSet(rawValue: 1 << 7)
    public static let homeAppliance = MeshClassificationSet(rawValue: 1 << 8)
    public static let seat          = MeshClassificationSet(rawValue: 1 << 9)
    public static let table         = MeshClassificationSet(rawValue: 1 << 10)
    
    // Decoration
    public static let plant         = MeshClassificationSet(rawValue: 1 << 11)
    public static let tv            = MeshClassificationSet(rawValue: 1 << 12)
    
    // Unknown
    public static let none          = MeshClassificationSet(rawValue: 1 << 13)
    
    // Use literal form for OptionSet composition
    public static let all: MeshClassificationSet = [
        .ceiling, .door, .floor, .stairs, .wall, .window,
        .bed, .cabinet, .homeAppliance, .seat, .table,
        .plant, .tv, .none
    ]
    
    public init(rawValue: Int) { self.rawValue = rawValue }
}

#if os(visionOS)
extension MeshAnchor.MeshClassification {
    var toMeshClassificationSet: MeshClassificationSet {
        switch self {
        case .ceiling:       return .ceiling
        case .door:          return .door
        case .floor:         return .floor
        case .stairs:        return .stairs
        case .wall:          return .wall
        case .window:        return .window
        case .bed:           return .bed
        case .cabinet:       return .cabinet
        case .homeAppliance: return .homeAppliance
        case .seat:          return .seat
        case .table:         return .table
        case .plant:         return .plant
        case .tv:            return .tv
        case .none:          return .none
        @unknown default:    return .none
        }
    }
}
#elseif os(iOS)
extension ARMeshClassification {
    var toMeshClassificationSet: MeshClassificationSet {
        switch self {
        case .ceiling:       return .ceiling
        case .door:          return .door
        case .floor:         return .floor
        case .wall:          return .wall
        case .window:        return .window
        case .seat:          return .seat
        case .table:         return .table
        case .none:          return .none
        @unknown default:    return .none
        }
    }
}
#endif
