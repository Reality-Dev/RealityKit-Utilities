import simd

// MARK: - Robust normal estimation utilities

@inline(__always)
func isFinite3(_ v: simd_float3) -> Bool {
    v.x.isFinite && v.y.isFinite && v.z.isFinite
}

@inline(__always)
func safeNormalize(_ v: simd_float3) -> simd_float3 {
    let l2 = simd_length_squared(v)
    return l2 > 1e-12 ? v / sqrt(l2) : simd_float3(0, 1, 0)
}

/// Area-weighted average of face normals from polygon indices.
/// Works for triangles or n-gons (uses a fan around vertex 0).
func areaWeightedFaceNormal(
    positions: [SIMD3<Float>],
    faceIndices: [UInt32],
    indexCounts: [UInt8]
) -> simd_float3 {
    var sum = simd_float3.zero
    var cursor = 0
    for countU8 in indexCounts {
        let c = Int(countU8)
        if c >= 3 {
            let i0 = Int(faceIndices[cursor + 0])
            let p0 = positions[i0]
            // triangle fan: (p0, p1, p2), (p0, p2, p3), ...
            for k in 1..<(c - 1) {
                let i1 = Int(faceIndices[cursor + k])
                let i2 = Int(faceIndices[cursor + k + 1])
                let p1 = positions[i1]
                let p2 = positions[i2]
                let n = simd_cross(p1 - p0, p2 - p0)
                if isFinite3(n) { sum += n }
            }
        }
        cursor += c
    }
    return safeNormalize(sum)
}

/// PCA plane normal for positions (smallest-variance eigenvector).
func pcaPlaneNormal(_ positions: [SIMD3<Float>]) -> simd_float3 {
    // mean
    var mean = simd_float3.zero
    for p in positions { mean += p }
    mean /= Float(max(positions.count, 1))

    // covariance
    var C = simd_float3x3(0)
    for p in positions {
        let d = p - mean
        C += simd_float3x3(columns: (d * d.x, d * d.y, d * d.z))
    }
    C = C * (1.0 / Float(max(positions.count, 1)))

    let (V, lambda) = jacobiEigenSymmetric3x3(C)
    // smallest eigenvalue → plane normal
    let order = [0,1,2].sorted { lambda[$0] < lambda[$1] }
    let idx = order[0]
    let col: simd_float3
    switch idx {
    case 0: col = V.columns.0
    case 1: col = V.columns.1
    default: col = V.columns.2
    }
    return safeNormalize(col)
}

/// Robust average normal:
/// 1) finite vertex normals average
/// 2) area-weighted face normals
/// 3) PCA plane normal (fallback)
func robustAverageNormal(
    positions: [SIMD3<Float>],
    normals: [SIMD3<Float>],
    faceIndices: [UInt32],
    indexCounts: [UInt8]
) -> simd_float3 {
    // 1) sanitized vertex normals
    var sum = simd_float3.zero
    var count: Float = 0
    for n in normals where isFinite3(n) {
        sum += n; count += 1
    }
    var avg = count > 0 ? safeNormalize(sum / count) : simd_float3.zero
    if simd_length_squared(avg) > 1e-12 { return avg }

    // 2) area-weighted faces
    let areaN = areaWeightedFaceNormal(positions: positions, faceIndices: faceIndices, indexCounts: indexCounts)
    if simd_length_squared(areaN) > 1e-12 { return areaN }

    // 3) PCA plane normal
    return pcaPlaneNormal(positions)
}


