import simd

// MARK: - Helpers used by both Accelerated and Scalar paths
// These compute raw per-vertex (u,v) arrays for non-planar projections.
// Normalization/tiling/flip + interleaving are handled by the UVGenerator implementations.

// Box / cubic mapping: pick a face per-vertex based on dominant |normal| component.
// U,V come from the two axes of that face in world space.
@inlinable
func uvBoxWorld(
    positions: [SIMD3<Float>],
    normals: [SIMD3<Float>]
) -> (u:[Float], v:[Float]) {
    let n = positions.count
    var u = [Float](repeating: 0, count: n)
    var v = [Float](repeating: 0, count: n)
    for i in 0..<n {
        let p = positions[i]
        let an = abs(normals[i])
        if an.x >= an.y && an.x >= an.z {
            // ±X → project to YZ
            u[i] = p.z; v[i] = p.y
        } else if an.y >= an.x && an.y >= an.z {
            // ±Y → project to XZ
            u[i] = p.x; v[i] = p.z
        } else {
            // ±Z → project to XY
            u[i] = p.x; v[i] = p.y
        }
    }
    return (u, v)
}

// Cylindrical mapping around a given axis through a center.
// Returns raw U = angle (radians, seam-unwrapped) and V = height (meters). Normalization happens later.
@inlinable
func uvCylindrical(
    positions: [SIMD3<Float>],
    axis aIn: SIMD3<Float>,
    center c: SIMD3<Float>
) -> (u:[Float], v:[Float]) {
    let a = simd_normalize(aIn)
    let helper: SIMD3<Float> = abs(a.y) < 0.9 ? SIMD3<Float>(0,1,0) : SIMD3<Float>(1,0,0)
    let xhat = simd_normalize(simd_cross(helper, a))
    let zhat = simd_normalize(simd_cross(a, xhat))

    var angle = [Float](repeating: 0, count: positions.count)
    var v =    [Float](repeating: 0, count: positions.count)

    for i in 0..<positions.count {
        let q = positions[i] - c
        let px = simd_dot(q, xhat)
        let pz = simd_dot(q, zhat)
        angle[i] = atan2(pz, px)  // [-π, π]
        v[i] = simd_dot(q, a)     // height
    }
    // unwrap
    if angle.count > 1 {
        let twoPi = 2 * Float.pi
        for i in 1..<angle.count {
            let d = angle[i] - angle[i-1]
            if d >  Float.pi { angle[i] -= twoPi }
            if d < -Float.pi { angle[i] += twoPi }
        }
    }
    return (angle, v)
}

// Spherical mapping about a center. Returns raw U = θ (radians, seam-unwrapped), V = φ (radians).
@inlinable
func uvSpherical(
    positions: [SIMD3<Float>],
    center c: SIMD3<Float>
) -> (u:[Float], v:[Float]) {
    var u = [Float](repeating: 0, count: positions.count)
    var v = [Float](repeating: 0, count: positions.count)
    for i in 0..<positions.count {
        let q = positions[i] - c
        let r = max(simd_length(q), 1e-6)
        let nx = q.x / r, ny = q.y / r, nz = q.z / r
        let theta = atan2(nz, nx)          // [-π, π]
        let phi   = acos(max(-1, min(1, ny))) // [0, π]
        u[i] = theta
        v[i] = phi
    }
    // unwrap θ
    if u.count > 1 {
        let twoPi = 2 * Float.pi
        for i in 1..<u.count {
            let d = u[i] - u[i-1]
            if d >  Float.pi { u[i] -= twoPi }
            if d < -Float.pi { u[i] += twoPi }
        }
    }
    return (u, v)
}

// Camera/projective mapping using a view-projection matrix (world -> clip).
// Returns U,V already in [0,1] (NDC remapped), but we still run through generator for tiling/flip consistency.
@inlinable
func uvCameraProject(
    positions: [SIMD3<Float>],
    viewProjection: simd_float4x4
) -> (u:[Float], v:[Float]) {
    var u = [Float](repeating: 0, count: positions.count)
    var v = [Float](repeating: 0, count: positions.count)
    for i in 0..<positions.count {
        let h = simd_float4(positions[i], 1)
        let clip = viewProjection * h
        let ndc = clip / max(clip.w, 1e-6)  // [-1,1]
        u[i] = 0.5 * (ndc.x + 1)            // [0,1]
        v[i] = 0.5 * (1 - ndc.y)            // [0,1], V-down image space
    }
    return (u, v)
}

// MARK: - Lightweight heuristics (automatic projection chooser)

/// Returns `.worldXZ` for horizontal surfaces, `.worldXY` for vertical, cylinder for rod-like,
/// box for near-isotropic clusters, otherwise defaults to planar-from-average-normal.
@inlinable
func chooseProjection(
    positions: [SIMD3<Float>],
    normals: [SIMD3<Float>]
) -> UVProjectionBasis {
    // Gravity alignment via average normal
    let nAvg: simd_float3 = {
        if normals.isEmpty { return simd_float3(0,1,0) }
        let s = normals.reduce(simd_float3.zero, +) / Float(normals.count)
        return simd_length_squared(s) > 1e-12 ? simd_normalize(s) : simd_float3(0,1,0)
    }()
    let up = simd_float3(0,1,0)
    let align = abs(simd_dot(nAvg, up))
    if align > 0.85 { return .worldXZ } // horizontal
    if align < 0.25 { return .worldXY } // vertical

    // PCA aspect heuristic
    let (eigVecs, eigVals, _) = pca3Positions(positions)
    let l0 = eigVals.x, l1 = eigVals.y, l2 = max(eigVals.z, 1e-6)
    let r01 = l0 / max(l1, 1e-6), r12 = l1 / l2

    if r12 > 8 { return .fromAverageNormal }               // very thin → planar
    if r01 > 8 && r12 < 4 { return .cylindrical(axis: eigVecs.columns.0, center: nil) } // rod-like
    if abs(l0 - l2) / max(l0, 1e-6) < 0.15 { return .boxWorld } // near-isotropic → box
    return .fromAverageNormal
}

// MARK: - PCA utilities (symmetric 3x3)

/// PCA over positions: returns eigenvectors (columns), eigenvalues (descending), and mean.
/// This variant is tuned for positions only (no need for full covariance API elsewhere).
@inlinable
func pca3Positions(_ data: [simd_float3]) -> (vectors: simd_float3x3, values: simd_float3, mean: simd_float3) {
    precondition(!data.isEmpty, "pca3Positions requires at least one point")
    // Mean
    var mean = simd_float3.zero
    for p in data { mean += p }
    mean /= Float(data.count)

    // Covariance (symmetric)
    var C = simd_float3x3(0)
    for p in data {
        let d = p - mean
        C += simd_float3x3(columns: (d * d.x, d * d.y, d * d.z))
    }
    C = C * (1.0 / Float(max(data.count, 1)))

    let (V, lambda) = jacobiEigenSymmetric3x3(C)
    let lambdaArr = [lambda.x, lambda.y, lambda.z]
    let order = [0,1,2].sorted { lambdaArr[$0] > lambdaArr[$1] }
    func getCol(_ i: Int) -> simd_float3 {
        switch i {
        case 0: return V.columns.0
        case 1: return V.columns.1
        case 2: return V.columns.2
        default: fatalError("Invalid column index")
        }
    }
    let e0 = getCol(order[0])
    let e1 = getCol(order[1])
    let e2 = getCol(order[2])
    let vals = simd_float3(lambdaArr[order[0]], lambdaArr[order[1]], lambdaArr[order[2]])
    return (simd_float3x3(columns: (e0, e1, e2)), vals, mean)
}

/// Principal axis (highest variance direction) from positions using PCA.
@inlinable
func principalAxis(_ data: [simd_float3]) -> simd_float3 {
    let (V, _, _) = pca3Positions(data)
    return V.columns.0
}

/// Jacobi eigen-decomposition for symmetric 3x3. Returns eigenvectors in columns and eigenvalues as float3.
@inlinable
func jacobiEigenSymmetric3x3(_ A: simd_float3x3, iters: Int = 12) -> (V: simd_float3x3, D: simd_float3) {
    // Make symmetric numerically.
    var a = 0.5 * (A + A.transpose)
    var V = simd_float3x3(1)

    for _ in 0..<iters {
        let a01 = abs(a[0,1]), a02 = abs(a[0,2]), a12 = abs(a[1,2])
        var p = 0, q = 1
        if a02 > a01 && a02 >= a12 { p = 0; q = 2 }
        else if a12 > a01 { p = 1; q = 2 }
        if abs(a[p,q]) < 1e-10 { break }

        let app = a[p,p], aqq = a[q,q], apq = a[p,q]
        let tau = (aqq - app) / (2 * apq)
        let t = copysign(1.0 / (abs(tau) + sqrt(1 + tau*tau)), tau)
        let c = Float(1.0) / sqrt(1 + t*t)
        let s = c * t

        // Rotate rows/cols p,q
        for k in 0..<3 where k != p && k != q {
            let aik = a[min(k,p), max(k,p)]
            let akq = a[min(k,q), max(k,q)]
            let rik = c * aik - s * akq
            let rkq = s * aik + c * akq
            a[min(k,p), max(k,p)] = rik
            a[min(k,q), max(k,q)] = rkq
        }
        let app2 = c*c*app - 2*c*s*apq + s*s*aqq
        let aqq2 = s*s*app + 2*c*s*apq + c*c*aqq
        a[p,p] = app2
        a[q,q] = aqq2
        a[p,q] = 0

        var vp: simd_float3
        var vq: simd_float3
        switch p {
        case 0: vp = V.columns.0
        case 1: vp = V.columns.1
        case 2: vp = V.columns.2
        default: fatalError("Invalid p index")
        }
        switch q {
        case 0: vq = V.columns.0
        case 1: vq = V.columns.1
        case 2: vq = V.columns.2
        default: fatalError("Invalid q index")
        }

        let vpNew = c*vp - s*vq
        let vqNew = s*vp + c*vq

        switch p {
        case 0: V.columns.0 = vpNew
        case 1: V.columns.1 = vpNew
        case 2: V.columns.2 = vpNew
        default: break
        }
        switch q {
        case 0: V.columns.0 = vqNew
        case 1: V.columns.1 = vqNew
        case 2: V.columns.2 = vqNew
        default: break
        }
    }
    return (V, simd_float3(a[0,0], a[1,1], a[2,2]))
}
