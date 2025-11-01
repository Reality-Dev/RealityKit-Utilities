import RealityKit
#if canImport(Accelerate)
import Accelerate

// MARK: - Accelerate implementation (vDSP + vForce where useful)

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

    // MARK: - Accelerated non-planar projections

    /// Computes cylindrical UVs using vDSP/vForce. Returns raw U (angle in radians, seam-unwrapped) and V (height in meters).
    @inlinable
    func cylindricalUVs(
        positions: [SIMD3<Float>],
        axis aIn: SIMD3<Float>,
        center c: SIMD3<Float>
    ) -> (u: [Float], v: [Float]) {
        let a = simd_normalize(aIn)

        // Build orthonormal frame (x̂, ẑ) around axis a
        let helper: SIMD3<Float> = abs(a.y) < 0.9 ? SIMD3<Float>(0,1,0) : SIMD3<Float>(1,0,0)
        let xhat = simd_normalize(simd_cross(helper, a))
        let zhat = simd_normalize(simd_cross(a, xhat))

        let n = positions.count
        var xs = [Float](repeating: 0, count: n)
        var ys = [Float](repeating: 0, count: n)
        var zs = [Float](repeating: 0, count: n)
        for i in 0..<n { xs[i] = positions[i].x - c.x; ys[i] = positions[i].y - c.y; zs[i] = positions[i].z - c.z }

        // Dot products with vDSP
        var px = dotSOA(x: xs, y: ys, z: zs, axis: xhat)
        var pz = dotSOA(x: xs, y: ys, z: zs, axis: zhat)
        let h  = dotSOA(x: xs, y: ys, z: zs, axis: a) // height along axis

        // Angle = atan2(pz, px) using vForce
        var u = [Float](repeating: 0, count: n)
        var len32 = Int32(n)
        vvatan2f(&u, pz, px, &len32) // u in [-π, π]

        // Simple phase-unwrapping to avoid seam jumps
        if n > 1 {
            let twoPi = 2 * Float.pi
            for i in 1..<n {
                var d = u[i] - u[i - 1]
                if d >  Float.pi { u[i] -= twoPi }
                if d < -Float.pi { u[i] += twoPi }
            }
        }
        return (u, h)
    }

    /// Computes spherical UVs using vDSP/vForce. Returns raw U (θ in radians, seam-unwrapped) and V (φ in radians).
    @inlinable
    func sphericalUVs(
        positions: [SIMD3<Float>],
        center c: SIMD3<Float>
    ) -> (u: [Float], v: [Float]) {
        let n = positions.count
        var xs = [Float](repeating: 0, count: n)
        var ys = [Float](repeating: 0, count: n)
        var zs = [Float](repeating: 0, count: n)
        for i in 0..<n { xs[i] = positions[i].x - c.x; ys[i] = positions[i].y - c.y; zs[i] = positions[i].z - c.z }

        // r = sqrt(x^2 + y^2 + z^2)
        var x2 = [Float](repeating: 0, count: n)
        var y2 = [Float](repeating: 0, count: n)
        var z2 = [Float](repeating: 0, count: n)
        vDSP_vsq(xs, 1, &x2, 1, vDSP_Length(n))
        vDSP_vsq(ys, 1, &y2, 1, vDSP_Length(n))
        vDSP_vsq(zs, 1, &z2, 1, vDSP_Length(n))
        var sum = [Float](repeating: 0, count: n)
        vDSP_vadd(x2, 1, y2, 1, &sum, 1, vDSP_Length(n))
        vDSP_vadd(sum, 1, z2, 1, &sum, 1, vDSP_Length(n))
        var r = [Float](repeating: 0, count: n)
        var n32 = Int32(n)
        vvsqrtf(&r, sum, &n32)

        // Guard small r
        var eps: Float = 1e-6
        vDSP_vthr(r, 1, &eps, &r, 1, vDSP_Length(n)) // r = max(r, eps)

        // Normalize components by r
        var nx = [Float](repeating: 0, count: n)
        var ny = [Float](repeating: 0, count: n)
        var nz = [Float](repeating: 0, count: n)
        vDSP_vdiv(r, 1, xs, 1, &nx, 1, vDSP_Length(n))
        vDSP_vdiv(r, 1, ys, 1, &ny, 1, vDSP_Length(n))
        vDSP_vdiv(r, 1, zs, 1, &nz, 1, vDSP_Length(n))

        // θ = atan2(nz, nx), φ = acos(ny)
        var u = [Float](repeating: 0, count: n)
        var v = [Float](repeating: 0, count: n)
        vvatan2f(&u, nz, nx, &n32) // [-π, π]
        // clamp ny to [-1,1] before acos
        var ones = [Float](repeating: 1, count: n)
        var negOnes = [Float](repeating: -1, count: n)
        vDSP_vclip(ny, 1, &negOnes, &ones, &ny, 1, vDSP_Length(n))
        vvacosf(&v, ny, &n32)      // [0, π]

        // Unwrap θ to avoid seam jumps
        if n > 1 {
            let twoPi = 2 * Float.pi
            for i in 1..<n {
                var d = u[i] - u[i - 1]
                if d >  Float.pi { u[i] -= twoPi }
                if d < -Float.pi { u[i] += twoPi }
            }
        }
        return (u, v)
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
