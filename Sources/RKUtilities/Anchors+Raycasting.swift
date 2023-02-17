/*
See the LICENSE file and the LICENSE ORIGINS folder for this sample’s licensing information.
 */

import RealityKit

#if canImport(ARKit)
import ARKit

// MARK: - ARPlaneAnchor extensions
extension ARPlaneAnchor {
    func correspondingAnchorEntity(scene: Scene) -> AnchorEntity? {
        return scene.anchors.first(where: {$0.anchorIdentifier == self.identifier}) as? AnchorEntity
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
