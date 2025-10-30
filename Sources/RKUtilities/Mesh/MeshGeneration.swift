import ARKit
import RealityKit

@MainActor
public extension PlaneExtent {
    var boxShape: ShapeResource {
#if os(visionOS)
        return ShapeResource.generateBox(width: width, height: height, depth: 0.02)
#else
        return ShapeResource.generateBox(width: width, height: 0.02, depth: height)
#endif
    }
    var debugShape: MeshResource {
        return MeshResource.generateBox(width: width, height: height, depth: 0.02)
    }
}

@available(iOS 18.0, *)
@available(visionOS 1.0, *)
@MainActor
public extension MeshResource {
    
    private nonisolated static func generateDescriptor(
        from geom: any PlaneGeometry
    ) -> MeshDescriptor {
        var desc = MeshDescriptor()
        
        let positions = geom.vertices
        
        desc.positions = .init(positions)
        
        let normalValues = Array(repeating: simd_float3(0, 1, 0), count: positions.count)
        
        desc.normals = .init(normalValues)
        
        let indexCounts = (0..<geom.faceCount).map { _ in UInt8(geom.vertexCountPerFace) }

        //!! Can we use triangles here?
        desc.primitives = .polygons(indexCounts, geom.faceIndices32)
        
        return desc
    }
    
    nonisolated static func generate(
        from geom: any PlaneGeometry
    ) async throws -> MeshResource {
        
        let desc = generateDescriptor(from: geom)

        // While this claims to be available on iOS 15 and up, this is a bug from Apple, and will crash on anything below iOS 18.
        return try await MeshResource(from: [desc])
    }
    
    nonisolated static func generate(
        from geom: any MeshGeometry
    ) async throws -> MeshResource {
        
        var desc = MeshDescriptor()
        
        let positions = geom.vertices.asSIMD3(ofType: Float.self)
        
        desc.positions = .init(positions)
        
        let normalValues = geom.normals.asSIMD3(ofType: Float.self)
        
        desc.normals = .init(normalValues)
        
        let indexCounts = (0..<geom.faces.count).map { _ in UInt8(geom.faces.vertexCountPerFace) }
        
        let faceIndices = (0..<geom.faces.count * geom.faces.vertexCountPerFace).map {
            geom.faces.buffer.contents()
                .advanced(by: $0 * geom.faces.bytesPerIndex)
                .assumingMemoryBound(to: UInt32.self).pointee
        }

        //!! Can we use triangles here?
        desc.primitives = .polygons(indexCounts, faceIndices)

        // While this claims to be available on iOS 15 and up, this is a bug from Apple, and will crash on anything below iOS 18.
        return try await MeshResource(from: [desc])
    }
}

// While this compiles on iOS 17, this is a bug from Apple, and will crash on anything below iOS 18.
@available(iOS 18.0, *)
@available(visionOS 1.0, *)
@MainActor
public
extension ShapeResource {
    
    nonisolated static func generateStaticMesh(
        from geom: PlaneGeometry
    ) async throws -> ShapeResource {
        return try await generateStaticMesh(positions: geom.vertices,
                                            faceIndices: geom.faceIndices16)
    }
    
    nonisolated static func generateStaticMesh(
        from planeAnchor: any HasPlaneGeometry
    ) async throws -> ShapeResource {
        try await generateStaticMesh(from: planeAnchor.geometry)
    }
}

// MARK: - Convenience Methods
@available(iOS 18.0, *)
@available(visionOS 1.0, *)
@MainActor
public
extension MeshResource {
    nonisolated static func generate(
        from planeAnchor: any HasPlaneGeometry
    ) async throws -> MeshResource {
        try await generate(from: planeAnchor.geometry)
    }
    
    nonisolated static func generate(
        from meshAnchor: any HasMeshGeometry
    ) async throws -> MeshResource {
        try await generate(from: meshAnchor.geometry)
    }
}
