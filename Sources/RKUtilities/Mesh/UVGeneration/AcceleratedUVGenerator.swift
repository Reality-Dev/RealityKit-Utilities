import RealityKit
#if canImport(Accelerate)
import Accelerate

// MARK: - Accelerate implementation (vDSP)

public struct AcceleratedUVGenerator: UVGenerator {

    /// Project positions → separate U,V arrays via vDSP, then normalize/tile/flip, then interleave.
    @inlinable
    public func generateUVs(
        positions: [SIMD3<Float>],
        uAxis: simd_float3,
        vAxis: simd_float3,
        normalizeUVs: Bool,
        tiling: SIMD2<Float>,
        flipV: Bool
    ) -> [SIMD2<Float>] {

        // Deinterleave to SoA for vDSP
        let n = positions.count
        var x = [Float](repeating: 0, count: n)
        var y = [Float](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n)
        for i in 0..<n { x[i] = positions[i].x; y[i] = positions[i].y; z[i] = positions[i].z }

        // u = dot(p, uAxis), v = dot(p, vAxis)
        var u = dotSOA(x: x, y: y, z: z, axis: uAxis)
        var v = dotSOA(x: x, y: y, z: z, axis: vAxis)

        // Normalize, tile, flip
        if normalizeUVs { normalize01(u: &u, v: &v) }
        tileAndFlip(u: &u, v: &v, tiling: tiling, flipV: flipV)

        return interleave(u: u, v: v)
    }

    /// If caller already has U and V, do the vector ops directly.
    @inlinable
    public func generateUVs(
        u: [Float],
        v: [Float],
        normalizeUVs: Bool,
        tiling: SIMD2<Float>,
        flipV: Bool
    ) -> [SIMD2<Float>] {
        precondition(u.count == v.count)
        var uu = u, vv = v
        if normalizeUVs { normalize01(u: &uu, v: &vv) }
        tileAndFlip(u: &uu, v: &vv, tiling: tiling, flipV: flipV)
        return interleave(u: uu, v: vv)
    }

    // MARK: vDSP building blocks

    @inlinable
    internal func dotSOA(x: [Float], y: [Float], z: [Float], axis: simd_float3) -> [Float] {
        let n = vDSP_Length(x.count)
        var out = [Float](repeating: 0, count: x.count)
        var tmp = [Float](repeating: 0, count: x.count)

        var ax = axis.x, ay = axis.y, az = axis.z
        vDSP_vsmul(x, 1, &ax, &out, 1, n)      // out = ax * x
        vDSP_vsmul(y, 1, &ay, &tmp, 1, n); vDSP_vadd(out, 1, tmp, 1, &out, 1, n)
        vDSP_vsmul(z, 1, &az, &tmp, 1, n); vDSP_vadd(out, 1, tmp, 1, &out, 1, n)
        return out
    }

    /// Normalize U,V into [0,1] using vDSP reductions and affine transforms.
    @inlinable
    internal func normalize01(u: inout [Float], v: inout [Float]) {
        let n = vDSP_Length(u.count)
        var minU: Float = 0, maxU: Float = 0
        var minV: Float = 0, maxV: Float = 0
        vDSP_minv(u, 1, &minU, n); vDSP_maxv(u, 1, &maxU, n)
        vDSP_minv(v, 1, &minV, n); vDSP_maxv(v, 1, &maxV, n)

        var du = max(maxU - minU, 1e-6)
        var dv = max(maxV - minV, 1e-6)
        var negMinU = -minU, negMinV = -minV

        vDSP_vsadd(u, 1, &negMinU, &u, 1, n); vDSP_vsdiv(u, 1, &du, &u, 1, n)
        vDSP_vsadd(v, 1, &negMinV, &v, 1, n); vDSP_vsdiv(v, 1, &dv, &v, 1, n)
    }

    /// Apply tiling and optional V-flip with vDSP.
    @inlinable
    internal func tileAndFlip(u: inout [Float], v: inout [Float], tiling: SIMD2<Float>, flipV: Bool) {
        let n = vDSP_Length(u.count)
        var tileU = tiling.x, tileV = tiling.y
        vDSP_vsmul(u, 1, &tileU, &u, 1, n)
        vDSP_vsmul(v, 1, &tileV, &v, 1, n)
        if flipV {
            var minusOne: Float = -1, one: Float = 1
            vDSP_vsmsa(v, 1, &minusOne, &one, &v, 1, n) // v = (-1)*v + 1
        }
    }

    /// Interleave U and V into `[SIMD2<Float>]` efficiently.
    @inlinable
    internal func interleave(u: [Float], v: [Float]) -> [SIMD2<Float>] {
        var out = [SIMD2<Float>](repeating: .zero, count: u.count)
        for i in 0..<u.count { out[i] = SIMD2<Float>(u[i], v[i]) }
        return out
    }
}
#endif // canImport(Accelerate)
