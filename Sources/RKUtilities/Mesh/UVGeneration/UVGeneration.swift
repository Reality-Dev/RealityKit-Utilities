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

    // Additional options (kept backward compatible with your existing API):
    /// Automatically pick a sensible projection basis using lightweight heuristics (gravity, PCA).
    case automatic
    /// Planar projection using a local frame (translation + rotation). Useful when you know the exact frame.
    case planar(projection: UVPlanarProjection)
    /// Per-vertex box mapping based on dominant normal component (±X/±Y/±Z).
    case boxWorld
    /// Cylindrical mapping around an axis through `center`. If values are nil, fall back to PCA hints.
    case cylindrical(axis: simd_float3? = nil, center: simd_float3? = nil)
    /// Spherical mapping about `center`. If nil, uses the data PCA center.
    case spherical(center: simd_float3? = nil)
    /// Camera/projective mapping using a view-projection matrix (world -> clip).
    case camera(viewProjection: simd_float4x4)
}

/// Rotation + translation that define a local planar frame.
/// Columns of `rotation.matrix` are the local axes; project after subtracting `translation`.
public struct UVPlanarProjection {
    public var translation: simd_float3
    public var rotation: simd_quatf
    public init(translation: simd_float3, rotation: simd_quatf) {
        self.translation = translation
        self.rotation = rotation
    }
}

// MARK: - Orthonormal basis helpers (unchanged logic)

// Helpers moved to `RobustNormals.swift`

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

    // New cases that return planar axes directly (the rest are handled in the body below):
    case .automatic:
        // Use the average normal as a quick hint; the full automatic path below may override this with non-planar projections.
        let n = simd_length(avgNormal) > 0.0001 ? simd_normalize(avgNormal) : simd_float3(0,1,0)
        return orthonormalBasis(for: n)
    case .planar(let planar):
        // Columns of rotation.matrix are the local axes; take the first two for U,V
        let R = simd_float3x3(planar.rotation)
        return (simd_normalize(R.columns.0), simd_normalize(R.columns.1))
    case .boxWorld, .cylindrical, .spherical, .camera:
        // These are non-planar projections; axes are resolved later per-vertex.
        // Return a harmless default to satisfy the signature.
        let n = simd_length(avgNormal) > 0.0001 ? simd_normalize(avgNormal) : simd_float3(0,1,0)
        return orthonormalBasis(for: n)
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

    /// Convenience when you already have scalar U and V arrays (e.g. box/cyl/sphere/camera or plane XZ/XY mapping).
    func generateUVs(
        u: [Float],
        v: [Float],
        normalizeUVs: Bool,
        tiling: SIMD2<Float>,
        flipV: Bool
    ) -> [SIMD2<Float>]
    
    /// Compute cylindrical UVs using the appropriate backend. Returns raw U,V arrays before normalization/tiling/flip.
    func cylindricalUVs(positions: [SIMD3<Float>], axis: SIMD3<Float>, center: SIMD3<Float>) -> (u: [Float], v: [Float])
    
    /// Compute spherical UVs using the appropriate backend. Returns raw U,V arrays before normalization/tiling/flip.
    func sphericalUVs(positions: [SIMD3<Float>], center: SIMD3<Float>) -> (u: [Float], v: [Float])
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
@available(visionOS 1.0, *)
@MainActor
public extension MeshResource {

    /// Generate a MeshResource from MeshGeometry, adding UVs.
    /// - Parameters:
    ///   - geom: mesh geometry (conforming to `MeshGeometry`)
    ///   - projection: The projection mode (planar/box/cyl/spherical/camera/automatic).
    ///   - normalizeUVs: If true, remap UVs into [0,1] using the mesh's bounds in the projection domain.
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

        // --- UVs ---
        // Note: We support both planar and non-planar projections. For non-planar, we compute U,V arrays first,
        // then ask the generator to normalize/tile/flip and interleave them.
        let generator = UVGeneratorFactory.make(preferAccelerate: preferAccelerate)

        // Compute a robust average normal that resists degenerate/NaN normals.
        let avgN: simd_float3 = robustAverageNormal(
            positions: positions,
            normals: normals,
            faceIndices: faceIndices,
            indexCounts: indexCounts
        )

        // Optional automatic projection selection (lightweight heuristics).
        let chosenProjection: UVProjectionBasis = {
            switch projection {
            case .automatic:
                return chooseProjection(positions: positions, normals: normals)
            default:
                return projection
            }
        }()

        let uvs: [SIMD2<Float>]

        switch chosenProjection {

        // Planar family (use fast generator projection path)
        case .fromAverageNormal, .worldXY, .worldXZ, .worldYZ, .custom:
            let (uAxis, vAxis) = basis(for: chosenProjection, avgNormal: avgN)
            uvs = generator.generateUVs(
                positions: positions,
                uAxis: uAxis,
                vAxis: vAxis,
                normalizeUVs: normalizeUVs,
                tiling: tiling,
                flipV: flipV
            )

        case .planar(let p):
            // Apply translation by projecting in the local frame (subtract origin)
            let R = simd_float3x3(p.rotation)
            let uAxis = simd_normalize(R.columns.0)
            let vAxis = simd_normalize(R.columns.1)
            let local = positions.map { $0 - p.translation }
            uvs = generator.generateUVs(
                positions: local,
                uAxis: uAxis,
                vAxis: vAxis,
                normalizeUVs: normalizeUVs,
                tiling: tiling,
                flipV: flipV
            )

        // Non-planar projections (compute U,V arrays first; let generator post-process)
        case .boxWorld:
            let (u, v) = uvBoxWorld(positions: positions, normals: normals)
            uvs = generator.generateUVs(
                u: u, v: v,
                normalizeUVs: normalizeUVs,
                tiling: tiling,
                flipV: flipV
            )

        case let .cylindrical(axisOpt, centerOpt):
            let (_, _, centerPCA) = pca3Positions(positions)
            let axis = axisOpt ?? principalAxis(positions)
            let center = centerOpt ?? centerPCA
            let (u, v) = generator.cylindricalUVs(positions: positions, axis: axis, center: center)
            uvs = generator.generateUVs(u: u, v: v, normalizeUVs: normalizeUVs, tiling: tiling, flipV: flipV)

        case let .spherical(centerOpt):
            let (_, _, centerPCA) = pca3Positions(positions)
            let center = centerOpt ?? centerPCA
            let (u, v) = generator.sphericalUVs(positions: positions, center: center)
            uvs = generator.generateUVs(u: u, v: v, normalizeUVs: normalizeUVs, tiling: tiling, flipV: flipV)

        case let .camera(mvp):
            let (u, v) = uvCameraProject(positions: positions, viewProjection: mvp)
            uvs = generator.generateUVs(
                u: u, v: v,
                normalizeUVs: normalizeUVs, // most of the time you'll keep this true
                tiling: tiling,
                flipV: flipV
            )
        case .automatic:
            assertionFailure("Auto should not be reached")
            // Fallback for release build.
            let (u, v) = uvBoxWorld(positions: positions, normals: normals)
            uvs = generator.generateUVs(
                u: u, v: v,
                normalizeUVs: normalizeUVs,
                tiling: tiling,
                flipV: flipV
            )
        }

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

// MARK: - Convenience for anchors

@available(iOS 18.0, *)
@available(visionOS 1.0, *)
@MainActor
public extension MeshResource {
    nonisolated static func generateWithUVs(
        from anchor: any HasMeshGeometry,
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
