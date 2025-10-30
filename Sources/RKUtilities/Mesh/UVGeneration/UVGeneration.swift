import ARKit
import simd
import RealityKit

// MARK: - Projection options

public enum UVProjectionBasis {
    /// Build U,V from the mesh's average normal (good general default)
    case fromAverageNormal
    /// Use fixed world axes regardless of mesh normal
    case worldXY, worldXZ, worldYZ
    /// Provide a custom orthonormal basis
    case custom(u: simd_float3, v: simd_float3)
}

// MARK: - Orthonormal basis helpers (unchanged logic)

@inlinable
internal func orthonormalBasis(for n: simd_float3) -> (u: simd_float3, v: simd_float3) {
    // Choose a helper axis least aligned with n to avoid degeneracy
    let helper: simd_float3 = abs(n.x) > abs(n.z) ? simd_float3(0,0,1) : simd_float3(1,0,0)
    let u = simd_normalize(simd_cross(helper, n))
    let v = simd_normalize(simd_cross(n, u))
    return (u, v)
}

@inlinable
internal func basis(for mode: UVProjectionBasis, avgNormal: simd_float3) -> (u: simd_float3, v: simd_float3) {
    switch mode {
    case .fromAverageNormal:
        let n = simd_length(avgNormal) > 0.0001 ? simd_normalize(avgNormal) : simd_float3(0,1,0)
        return orthonormalBasis(for: n)
    case .worldXY:
        return (simd_float3(1,0,0), simd_float3(0,1,0))
    case .worldXZ:
        return (simd_float3(1,0,0), simd_float3(0,0,1))
    case .worldYZ:
        return (simd_float3(0,1,0), simd_float3(0,0,1))
    case let .custom(u, v):
        // Assume caller passes orthonormal, otherwise normalize here
        let uu = simd_normalize(u)
        let vv = simd_normalize(v)
        return (uu, vv)
    }
}

// MARK: - UVGenerator Protocol

/// Strategy protocol for generating UVs, allowing Accelerate-backed and scalar implementations.
/// Implementations should be mathematically equivalent; only performance differs.
internal protocol UVGenerator {
    /// Project 3D positions onto a (u,v) basis, optionally normalize to [0,1], apply tiling, and flip V.
    /// - Parameters:
    ///   - positions: Vertex positions as `[SIMD3<Float>]`
    ///   - uAxis: Unit vector for the U axis in world/mesh space
    ///   - vAxis: Unit vector for the V axis in world/mesh space
    ///   - normalizeUVs: If true, remap into [0,1] using min/max over U and V
    ///   - tiling: Multiply final UVs by this factor (e.g. meters → texture tiles)
    ///   - flipV: Flip V to match image-space conventions
    /// - Returns: Interleaved `[SIMD2<Float>]` texture coordinates
    func generateUVs(
        positions: [SIMD3<Float>],
        uAxis: simd_float3,
        vAxis: simd_float3,
        normalizeUVs: Bool,
        tiling: SIMD2<Float>,
        flipV: Bool
    ) -> [SIMD2<Float>]

    /// Convenience when you already have scalar U and V arrays (e.g. plane XZ/XY mapping).
    func generateUVs(
        u: [Float],
        v: [Float],
        normalizeUVs: Bool,
        tiling: SIMD2<Float>,
        flipV: Bool
    ) -> [SIMD2<Float>]
}

// MARK: - Factory

/// Picks the best available UVGenerator for the current build, with an optional override.
internal enum UVGeneratorFactory {
    /// Create a UV generator. By default prefers Accelerate when available.
    /// - Parameter preferAccelerate: Set `false` to force scalar path (useful for tests / debugging).
    static func make(preferAccelerate: Bool = true) -> UVGenerator {
        #if canImport(Accelerate)
        if preferAccelerate { return AcceleratedUVGenerator() }
        return ScalarUVGenerator()
        #else
        return ScalarUVGenerator()
        #endif
    }
}

// MARK: - UV Generation

@available(iOS 18.0, *)
@MainActor
public extension MeshResource {

    /// Generate a MeshResource from MeshGeometry, adding planar UVs.
    /// - Parameters:
    ///   - geom: mesh geometry (conforming to `MeshGeometry`)
    ///   - projection: How to choose the (U,V) projection axes
    ///   - normalizeUVs: If true, remap UVs into [0,1] using the mesh's bounds in the projection plane
    ///   - tiling: Multiply the final UVs by this amount (use meters-as-UV when `normalizeUVs == false`)
    ///   - flipV: Flip V to match common image coordinate conventions
    ///   - preferAccelerate: Pass `false` to force the scalar implementation (handy for A/B or unit tests)
    /// - Note: By default, on visionOS 2.0, `MeshResource(from: meshAnchor)` does not provide any UV's. This fixes that.
    nonisolated static func generateWithUVs(
        from geom: any MeshGeometry,
        projection: UVProjectionBasis = .fromAverageNormal,
        normalizeUVs: Bool = true,
        tiling: SIMD2<Float> = .one,
        flipV: Bool = false,
        preferAccelerate: Bool = true
    ) async throws -> MeshResource {

        var desc = MeshDescriptor()

        // Positions / normals from existing helpers
        let positions = geom.vertices.asSIMD3(ofType: Float.self)
        let normals   = geom.normals.asSIMD3(ofType: Float.self)

        desc.positions = .init(positions)
        desc.normals   = .init(normals)

        // Topology (keep polygons if that's what you have)
        let indexCounts = (0..<geom.faces.count).map { _ in UInt8(geom.faces.vertexCountPerFace) }
        let faceIndices: [UInt32] = (0..<(geom.faces.count * geom.faces.vertexCountPerFace)).map {
            geom.faces.buffer.contents()
                .advanced(by: $0 * geom.faces.bytesPerIndex)
                .assumingMemoryBound(to: UInt32.self).pointee
        }
        desc.primitives = .polygons(indexCounts, faceIndices)

        // --- UVs via strategy ---
        let avgN = geom.avergeNormal
        let (uAxis, vAxis) = basis(for: projection, avgNormal: avgN)
        let generator = UVGeneratorFactory.make(preferAccelerate: preferAccelerate)
        let uvs = generator.generateUVs(
            positions: positions,
            uAxis: uAxis,
            vAxis: vAxis,
            normalizeUVs: normalizeUVs,
            tiling: tiling,
            flipV: flipV
        )
        desc.textureCoordinates = .init(uvs)

        // While this claims to be available on iOS 15 and up, this is a bug from Apple, and will crash on anything below iOS 18.
        return try await MeshResource(from: [desc])
    }

    /// Generate a MeshResource from a PlaneGeometry, adding UVs.
    /// For planes this is trivial: X maps to U, Z (iOS) or Y (visionOS) maps to V.
    nonisolated static func generateWithUVs(
        from plane: any PlaneGeometry,
        normalizeUVs: Bool = true,
        tiling: SIMD2<Float> = .one,
        flipV: Bool = false,
        preferAccelerate: Bool = true
    ) async throws -> MeshResource {

        var desc = MeshDescriptor()

        let positions = plane.vertices
        desc.positions = .init(positions)

        // Flat normals pointing "up"
        let normalValues = Array(repeating: simd_float3(0, 1, 0), count: positions.count)
        desc.normals = .init(normalValues)

        let indexCounts = (0..<plane.faceCount).map { _ in UInt8(plane.vertexCountPerFace) }
        desc.primitives = .polygons(indexCounts, plane.faceIndices32)

        // --- UVs for plane via strategy ---
        #if os(visionOS)
        let uArr = positions.map { $0.x }
        let vArr = positions.map { $0.y }
        #else
        let uArr = positions.map { $0.x }
        let vArr = positions.map { $0.z }
        #endif

        let generator = UVGeneratorFactory.make(preferAccelerate: preferAccelerate)
        let uvs = generator.generateUVs(
            u: uArr,
            v: vArr,
            normalizeUVs: normalizeUVs,
            tiling: tiling,
            flipV: flipV
        )
        desc.textureCoordinates = .init(uvs)

        // While this claims to be available on iOS 15 and up, this is a bug from Apple, and will crash on anything below iOS 18.
        return try await MeshResource(from: [desc])
    }
}

// MARK: - Convenience for anchors (unchanged API surface)

#if os(iOS)
@available(iOS 18.0, *)
@MainActor
public extension MeshResource {
    nonisolated static func generateWithUVs(
        from anchor: ARMeshAnchor,
        projection: UVProjectionBasis = .fromAverageNormal,
        normalizeUVs: Bool = true,
        tiling: SIMD2<Float> = .one,
        flipV: Bool = false,
        preferAccelerate: Bool = true
    ) async throws -> MeshResource {
        try await generateWithUVs(from: anchor.geometry,
                                  projection: projection,
                                  normalizeUVs: normalizeUVs,
                                  tiling: tiling,
                                  flipV: flipV,
                                  preferAccelerate: preferAccelerate)
    }
}
#elseif os(visionOS)
@MainActor
public extension MeshResource {
    nonisolated static func generateWithUVs(
        from anchor: MeshAnchor,
        projection: UVProjectionBasis = .fromAverageNormal,
        normalizeUVs: Bool = true,
        tiling: SIMD2<Float> = .one,
        flipV: Bool = false,
        preferAccelerate: Bool = true
    ) async throws -> MeshResource {
        try await generateWithUVs(from: anchor.geometry,
                                  projection: projection,
                                  normalizeUVs: normalizeUVs,
                                  tiling: tiling,
                                  flipV: flipV,
                                  preferAccelerate: preferAccelerate)
    }
}
#endif
