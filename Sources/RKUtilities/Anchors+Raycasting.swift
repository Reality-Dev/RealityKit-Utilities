/*
See the LICENSE file and the LICENSE ORIGINS folder for this sample’s licensing information.
 */

import RealityKit

#if canImport(ARKit)
import ARKit

// MARK: - ARCamera extensions
public extension ARCamera {
    /*
     For `ARCamera.transform`:
     The X-axis always points along the long axis of the device, from the front-facing camera toward the Home button. The y-axis points upward (with respect to UIDeviceOrientation.landscapeRight orientation), and the z-axis points away from the device on the screen side.
     Therefore in portrait mode, a transformation is required to generate the expected matrix (+Y-up).
     */
    ///When the device is in `UIDeviceOrientation.portrait` this property represents the transform of the camera with +Y up, +X to the right and -Z to the front.
    var portraitTransform: simd_float4x4 {
        let orientationShift = simd_quatf(angle: .pi / 2, axis: .roll)
        return simd_mul(self.transform, matrix_float4x4(orientationShift))
    }
}

// MARK: - ARPlaneAnchor extensions
extension ARPlaneAnchor {
    ///Convert from ARKit alignment to RealityKit alignment.
    public var targetAlignment: AnchoringComponent.Target.Alignment {
        switch self.alignment {
        case .horizontal:
            return .horizontal
        case .vertical:
            return .vertical
        @unknown default:
            return .any
        }
    }
    
    func correspondingAnchorEntity(scene: Scene) -> AnchorEntity? {
        return scene.anchors.first(where: {$0.anchorIdentifier == self.identifier}) as? AnchorEntity
    }
    
    var isOnCeiling: Bool {
        // Using the provided Entity did Not work. Its world position was always 0,0,0. So we make a new one.
        let ceilingCheckerEntity = Entity()
        ceilingCheckerEntity.transform.matrix = self.transform
        // Make sure this anchor is Not on the ceiling.
        let up = ceilingCheckerEntity.convert(position: [0, 1, 0], to: nil).y
        let anchorY = ceilingCheckerEntity.position.y
        guard (up - anchorY) > -0.5 else {
            return true
        }
        return false
    }
}

extension ARPlaneAnchor.Alignment: CustomStringConvertible {
    public var description: String {
        switch self {
        case .horizontal:
            return "horiztonal"
        case .vertical:
            return "vertical"
        @unknown default:
            return "unknown"
        }
    }
}


// MARK: - AnchorEntity extensions
public extension AnchorEntity {
    func correspondingARPlaneAnchor(session: ARSession) -> ARAnchor? {
        return session.currentFrame?.anchors.first(where: {$0.identifier == self.anchorIdentifier})
    }
}

// MARK: - ARView extensions
public extension ARView {
    /// This performs a raycast from the given screen point.
    /// - Parameters:
    ///   - point: The screen-space point from which to raycast into the scene.
    ///   - alignment: The target alignment for the raycast query (with respect to gravity). A raycast ignores potential targets with an alignment different than the one you specify in the raycast query.
    /// - Returns: An ARRaycastResult: Information about a real-world surface found by examining a point on the screen.
    func smartRaycast(from point: CGPoint,
                      alignment: ARRaycastQuery.TargetAlignment = .any) -> ARRaycastResult? {
        
        // Perform the raycast.
        guard let existingPlaneQuery = self.makeRaycastQuery(from: point,
                                                             allowing: .existingPlaneGeometry,
                                                             alignment: alignment)
        else {return nil}
        
        
        let results = self.session.raycast(existingPlaneQuery)
        
        // Check for a result on an existing plane geometry.
        if let existingPlaneGeometryResult = results.first(where: { $0.target == .existingPlaneGeometry }) {
            return existingPlaneGeometryResult
        }
        
        //As a primary fallback, look for results on estimated planes.
        //If the device has LiDAR, then this will intersect with the LiDAR scene mesh.
            guard let estimatedPlaneQuery = self.makeRaycastQuery(from: point,
                                                                  allowing: .estimatedPlane,
                                                                  alignment: alignment) else {return nil}
            if let estimatedPlaneResult = self.session.raycast(estimatedPlaneQuery).first {
                return estimatedPlaneResult
            }
        
        //As a secondary fallback, look for results on infinite horizontal planes.
        guard let infinitePlaneQuery = self.makeRaycastQuery(from: point,
                                                             allowing: .existingPlaneInfinite,
                                                             alignment: .horizontal) else {return nil}
        
        if let infinitePlaneResult = self.session.raycast(infinitePlaneQuery).first {
                return infinitePlaneResult
        }
        
        return nil
    }
}
#endif
