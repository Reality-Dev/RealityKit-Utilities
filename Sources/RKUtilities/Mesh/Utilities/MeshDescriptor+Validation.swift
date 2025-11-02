//
//  MeshDescriptorValidator.swift
//
//  A compact, RealityKit-native validator for MeshDescriptor.
//  Verifies structure, counts, bounds, materials, and common footguns
//  without ever crashing—even on malformed data.
//

import RealityKit

// MARK: - Public API

public struct MeshValidationReport: CustomStringConvertible {
    public let name: String
    public let vertexCount: Int
    public let faceCount: Int
    public let totalIndexCount: Int
    public var errors: [String] = []
    public var warnings: [String] = []

    public var isValid: Bool { errors.isEmpty }

    public var description: String {
        var lines: [String] = [
            "MeshValidationReport(name: \"\(name)\", vertices: \(vertexCount), faces: \(faceCount), indices: \(totalIndexCount))",
            "  errors(\(errors.count)):"
        ]
        lines += errors.map { "    • \($0)" }
        lines.append("  warnings(\(warnings.count)):")
        lines += warnings.map { "    • \($0)" }
        return lines.joined(separator: "\n")
    }
}

public enum MeshValidationError: Error, CustomStringConvertible {
    case invalid(report: MeshValidationReport)
    public var description: String {
        switch self {
        case .invalid(let r): return "MeshDescriptor failed validation:\n\(r)"
        }
    }
}

public extension MeshDescriptor {
    /// Validate structural correctness of a `MeshDescriptor`.
    /// - Parameter strict: if true, throws on any error; otherwise returns a report you can inspect.
    @discardableResult
    func validate(strict: Bool = true) throws -> MeshValidationReport {
        let vertexCount = positions.elements.count ?? 0
        let faceCount = primitives?.faceCount ?? 0
        let totalIndexCount = primitives?.totalIndexCount ?? 0

        var report = MeshValidationReport(
            name: name,
            vertexCount: vertexCount,
            faceCount: faceCount,
            totalIndexCount: totalIndexCount
        )

        // --- Presence ---
        if vertexCount == 0 {
            report.errors.append("No vertex positions set (`positions` is empty).")
        }
        guard let prim = primitives else {
            report.errors.append("No primitives set (`primitives == nil`).")
            if strict { throw MeshValidationError.invalid(report: report) }
            return report
        }

        // --- Normalize to polygons (counts + flat indices) ---
        let (counts, indices) = prim.asPolygons()

        // --- Invariants: length agreement ---
        let sum = counts.reduce(0) { $0 + Int($1) }
        if sum != indices.count {
            report.errors.append("counts/indices mismatch: counts sum \(sum) vs indices.count \(indices.count).")
            if strict { throw MeshValidationError.invalid(report: report) }
        }

        // --- Allowed polygon sizes & non-empty ---
        if counts.isEmpty {
            report.errors.append("Zero faces encoded (empty counts).")
        }
        if let zeroAt = counts.firstIndex(where: { $0 == 0 }) {
            report.errors.append("counts[\(zeroAt)] is 0 (invalid face).")
        }
        let invalidSizes = Set(counts.filter { $0 != 3 && $0 != 4 })
        if !invalidSizes.isEmpty {
            report.errors.append("Unsupported polygon sizes \(invalidSizes). Only 3 (tri) or 4 (quad) are supported.")
        }

        // --- Index bounds ---
        if vertexCount > 0, let firstOOB = indices.firstIndex(where: { $0 >= UInt32(vertexCount) }) {
            report.errors.append("Index out of bounds at indices[\(firstOOB)] = \(indices[firstOOB]) (vertexCount=\(vertexCount)).")
        }

        // --- Degenerate faces (duplicate verts) — safe stepping (no traps) ---
        var cursor = 0
        for (fi, c8) in counts.enumerated() {
            let c = Int(c8)
            // Guard bounds before slicing
            if cursor + c > indices.count {
                report.errors.append("Face \(fi) overruns indices: need \(c) starting at \(cursor), indices.count=\(indices.count).")
                break
            }
            // Skip invalid sizes (already recorded above), but advance cursor defensively
            if c != 3 && c != 4 {
                cursor += max(c, 0)
                continue
            }

            let face = indices[cursor ..< cursor + c]
            if Set(face).count != face.count {
                report.warnings.append("Degenerate face \(fi): repeated vertex indices \(Array(face)).")
            }
            cursor += c
        }

        // --- Materials shape ---
        switch materials {
        case .allFaces:
            break
        case .perFace(let faceMats):
            if faceMats.count != counts.count {
                report.errors.append("materials.perFace count \(faceMats.count) != face count \(counts.count).")
            }
        }

        // --- Attribute counts ---
        if let normals = normals, normals.count != vertexCount {
            report.errors.append("Normals count \(normals.count) != vertex count \(vertexCount).")
        }
        if let uvs = textureCoordinates, uvs.count != vertexCount {
            report.errors.append("UV count \(uvs.count) != vertex count \(vertexCount).")
        }

        // --- Finite checks (NaN/Inf) ---
        if let badPos = positions.elements.firstIndex(where: { !$0.x.isFinite || !$0.y.isFinite || !$0.z.isFinite }) {
            report.errors.append("Non-finite position at vertex \(badPos).")
        }
        if let badNrm = normals?.elements.firstIndex(where: { !$0.x.isFinite || !$0.y.isFinite || !$0.z.isFinite }) {
            report.warnings.append("Non-finite normal at vertex \(badNrm).")
        }

        // --- Specific arity checks for non-polygons encodings ---
        switch prim {
        case .triangles(let tri) where tri.count % 3 != 0:
            report.errors.append(".triangles index array not multiple of 3 (count=\(tri.count)).")
        case .trianglesAndQuads(let t, let q):
            if t.count % 3 != 0 { report.errors.append(".trianglesAndQuads.triangles not multiple of 3 (count=\(t.count)).") }
            if q.count % 4 != 0 { report.errors.append(".trianglesAndQuads.quads not multiple of 4 (count=\(q.count)).") }
        default:
            break
        }

        if strict, !report.isValid {
            throw MeshValidationError.invalid(report: report)
        }
        return report
    }
}
