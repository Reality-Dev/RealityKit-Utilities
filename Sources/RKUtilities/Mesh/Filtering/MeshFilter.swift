import ARKit
import RealityKit

public enum MeshBuildError: Error {
    case noFacesAfterFiltering
    case indicesEmpty
    case vertexCountPerFaceZero
    case indicesNotMultipleOfFace
    case normalsCountMismatch(expected: Int, got: Int)
}

public struct MeshFilter {
    /// Filter any MeshGeometry -> OwnedMeshGeometry
    nonisolated public static func filterFacesByClassification(
        from geom: any MeshGeometry,
        allowing allowedClassifications: MeshClassificationSet
    ) throws -> [UInt32] {
        
        let totalIndices = geom.faces.count * geom.faces.vertexCountPerFace
        let faceIndicesBase = geom.faces.buffer.contents()
        let vertexCountPerFace = geom.faces.vertexCountPerFace
        let bytesPerIndex = geom.faces.bytesPerIndex
        
        var keptFaceIndices: [UInt32] = []
        keptFaceIndices.reserveCapacity(totalIndices)
        
        let faceCount = totalIndices / vertexCountPerFace
        for face in 0..<faceCount {
            guard let cls = geom.classificationOf(faceWithIndex: face, of: MeshClassificationSet.self) else { continue }
            if allowedClassifications.contains(cls) {
                for v in 0..<vertexCountPerFace {
                    let i = face * vertexCountPerFace + v
                    let idx = readIndex(faceIndicesBase, at: i, bytesPerIndex: bytesPerIndex)
                    keptFaceIndices.append(UInt32(idx))
                }
            }
        }
        
        guard !keptFaceIndices.isEmpty else {
            throw MeshBuildError.indicesEmpty
        }
        
        return keptFaceIndices
    }
}

@available(iOS 18.0, *)
@available(visionOS 1.0, *)
@MainActor
public extension MeshResource {
    
    nonisolated static func generate(from anchor: any HasMeshGeometry,
                                     allowing allowedClassifications: MeshClassificationSet) async throws -> MeshResource {
        try await generate(from: anchor.geometry, allowing: allowedClassifications)
    }
    
    nonisolated static func generate(from geom: any MeshGeometry,
                                               allowing allowedClassifications: MeshClassificationSet) async throws -> MeshResource {
        let faceIndices = try MeshFilter.filterFacesByClassification(from: geom,
                                                                     allowing: allowedClassifications)
        
        var desc = generateDescriptor(from: geom)
        

        let indexCounts = (0..<geom.faces.count).map { _ in UInt8(geom.faces.vertexCountPerFace) }
        
        let vpf = geom.faces.vertexCountPerFace
        precondition(vpf == 3, "Only triangles expected")
        
        desc.primitives = .triangles(faceIndices)

        // While this claims to be available on iOS 15 and up, this is a bug from Apple, and will crash on anything below iOS 18.
        return try await MeshResource(from: [desc])
    }
    
    nonisolated static func generate(from geom: any MeshGeometry,
                                     allowing allowedClassifications: MeshClassificationSet,
                                     projection: UVProjectionBasis = .fromAverageNormal,
                                     normalizeUVs: Bool = true,
                                     tiling: SIMD2<Float> = .one,
                                     flipV: Bool = false,
                                     preferAccelerate: Bool = true) async throws -> MeshResource {
        
        let faceIndices = try MeshFilter.filterFacesByClassification(from: geom,
                                                                     allowing: allowedClassifications)
        
        var desc = generateDescriptor(from: geom)
  
        let vpf = geom.faces.vertexCountPerFace
        precondition(vpf == 3, "Only triangles expected")

        // If all triangles, this is the most canonical form:
        desc.primitives = .triangles(faceIndices)
        
        return try await applyUVs(to: desc,
                                  projection: projection,
                                  normalizeUVs: normalizeUVs,
                                  tiling: tiling,
                                  flipV: flipV,
                                  preferAccelerate: preferAccelerate)
    }
}
    
@available(iOS 18.0, *)
@available(visionOS 1.0, *)
@MainActor
public extension ShapeResource {
    
    nonisolated static func generateStaticMesh(from geom: any MeshGeometry,
                                               allowing allowedClassifications: MeshClassificationSet) async throws -> ShapeResource {
        
        let faceIndices32 = try MeshFilter.filterFacesByClassification(from: geom, allowing: allowedClassifications)
        
        let faceIndices16 = faceIndices32.map {UInt16($0)}
        
        let positions = geom.vertices.asSIMD3(ofType: Float.self)
        
        return try await ShapeResource.generateStaticMesh(positions: positions, faceIndices: faceIndices16)
    }

    /// Generic: MeshGeometry -> ShapeResource (no filtering)
    ///
    /// - Note: As of visionOS 26, RealityKit has `generateStaticMesh(from: MeshAnchor)` But not `generateStaticMesh(from: RoomAnchor)`
    nonisolated static func generateStaticMesh(from geom: any MeshGeometry) async throws -> ShapeResource {
        let positions = geom.vertices.asSIMD3(ofType: Float.self)

        let total = geom.faces.count * geom.faces.vertexCountPerFace
        let base = geom.faces.buffer.contents()
        let bpi = geom.faces.bytesPerIndex

        var indices16: [UInt16] = []
        indices16.reserveCapacity(total)
        for i in 0..<total {
            let idx = readIndex(base, at: i, bytesPerIndex: bpi)
            indices16.append(UInt16(idx))
        }


        return try await generateStaticMesh(positions: positions, faceIndices: indices16)
    }
}
