import RealityKit

// MARK: - Scalar implementation (no Accelerate)

public struct ScalarUVGenerator: UVGenerator {

    @inlinable
    internal func normalizeToUnitSquare(_ uvs: inout [SIMD2<Float>]) {
        // Safely normalizes UVs to [0,1] range component-wise.
        var minU = Float.infinity, minV = Float.infinity
        var maxU = -Float.infinity, maxV = -Float.infinity
        for uv in uvs {
            minU = min(minU, uv.x); minV = min(minV, uv.y)
            maxU = max(maxU, uv.x); maxV = max(maxV, uv.y)
        }
        let du = max(maxU - minU, 1e-6)
        let dv = max(maxV - minV, 1e-6)
        for i in 0..<uvs.count {
            let u = (uvs[i].x - minU) / du
            let v = (uvs[i].y - minV) / dv
            uvs[i] = SIMD2<Float>(u, v)
        }
    }

    @inlinable
    public func generateUVs(
        positions: [SIMD3<Float>],
        uAxis: simd_float3,
        vAxis: simd_float3,
        normalizeUVs: Bool,
        tiling: SIMD2<Float>,
        flipV: Bool
    ) -> [SIMD2<Float>] {
        // 1) Project
        var uvs = positions.map { p -> SIMD2<Float> in
            let u = simd_dot(p, uAxis)
            let v = simd_dot(p, vAxis)
            return SIMD2<Float>(u, v)
        }

        // 2) Normalize
        if normalizeUVs {
            normalizeToUnitSquare(&uvs)
        }

        // 3) Tiling + optional V-flip
        for i in 0..<uvs.count {
            var uv = uvs[i] * tiling
            if flipV { uv.y = 1.0 - uv.y }
            uvs[i] = uv
        }
        return uvs
    }

    @inlinable
    public func generateUVs(
        u: [Float],
        v: [Float],
        normalizeUVs: Bool,
        tiling: SIMD2<Float>,
        flipV: Bool
    ) -> [SIMD2<Float>] {
        precondition(u.count == v.count)
        var uvs = [SIMD2<Float>](repeating: .zero, count: u.count)
        for i in 0..<u.count { uvs[i] = SIMD2<Float>(u[i], v[i]) }

        if normalizeUVs {
            normalizeToUnitSquare(&uvs)
        }
        for i in 0..<uvs.count {
            var uv = uvs[i] * tiling
            if flipV { uv.y = 1.0 - uv.y }
            uvs[i] = uv
        }
        return uvs
    }
    
    @inlinable
    func cylindricalUVs(positions: [SIMD3<Float>], axis: SIMD3<Float>, center: SIMD3<Float>) -> (u: [Float], v: [Float]) {
        return uvCylindrical(positions: positions, axis: axis, center: center)
    }
    
    @inlinable
    func sphericalUVs(positions: [SIMD3<Float>], center: SIMD3<Float>) -> (u: [Float], v: [Float]) {
        return uvSpherical(positions: positions, center: center)
    }
}
