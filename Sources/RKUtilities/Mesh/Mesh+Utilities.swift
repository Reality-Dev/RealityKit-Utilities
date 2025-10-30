import RealityKit
import Accelerate

public
extension MeshGeometry {
    func vertex(at index: UInt32) -> (Float, Float, Float) {
        assert(vertices.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per vertex.")
        let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (vertices.stride * Int(index)))
        let vertex = vertexPointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
        return vertex
    }
    
    func normal(at index: UInt32) -> (Float, Float, Float) {
        assert(normals.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per vertex.")
        let vertexPointer = normals.buffer.contents().advanced(by: normals.offset + (normals.stride * Int(index)))
        let normal = vertexPointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
        return normal
    }
    
    /// To get the mesh's classification, the sample app parses the classification's raw data and instantiates an
    /// `ARMeshClassification` object. For efficiency, ARKit stores classifications in a Metal buffer in `ARMeshGeometry`.
    func classificationOf<T>(faceWithIndex index: Int,
                             of type: T.Type) -> T? where T : MeshClassification {
        guard let classification = classifications else { return .none }
        assert(classification.format == MTLVertexFormat.uchar, "Expected one unsigned char (one byte) per classification")
        let classificationPointer = classification.buffer.contents().advanced(by: classification.offset + (classification.stride * index))
        let classificationValue = Int(classificationPointer.assumingMemoryBound(to: CUnsignedChar.self).pointee)
        return T(rawValue: classificationValue)
    }
    
    func vertexIndicesOf(faceWithIndex faceIndex: Int) -> [UInt32] {
        assert(faces.bytesPerIndex == MemoryLayout<UInt32>.size, "Expected one UInt32 (four bytes) per vertex index")
        let vertexCountPerFace = faces.vertexCountPerFace
        let vertexIndicesPointer = faces.buffer.contents()
        var vertexIndices = [UInt32]()
        vertexIndices.reserveCapacity(vertexCountPerFace)
        for vertexOffset in 0..<vertexCountPerFace {
            let vertexIndexPointer = vertexIndicesPointer.advanced(by: (faceIndex * vertexCountPerFace + vertexOffset) * MemoryLayout<UInt32>.size)
            vertexIndices.append(vertexIndexPointer.assumingMemoryBound(to: UInt32.self).pointee)
        }
        return vertexIndices
    }
    
    func verticesOf(faceWithIndex index: Int) -> [(Float, Float, Float)] {
        let vertexIndices = vertexIndicesOf(faceWithIndex: index)
        let vertices = vertexIndices.map { vertex(at: $0) }
        return vertices
    }
    
    func normalsOf(faceWithIndex index: Int) -> [(Float, Float, Float)] {
        let vertexIndices = vertexIndicesOf(faceWithIndex: index)
        let normals = vertexIndices.map { normal(at: $0) }
        return normals
    }
    
    func centerOf(faceWithIndex index: Int) -> (Float, Float, Float) {
        let vertices = verticesOf(faceWithIndex: index)
        let sum = vertices.reduce((0, 0, 0)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2) }
        let geometricCenter = (sum.0 / 3, sum.1 / 3, sum.2 / 3)
        return geometricCenter
    }
    
    func normalOf(faceWithIndex index: Int) -> simd_float3 {
        let normals = normalsOf(faceWithIndex: index)
        let sum = normals.reduce((0, 0, 0)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2) }
        return [sum.0 / 3, sum.1 / 3, sum.2 / 3]
    }
    
    // For some reason the MeshAnchor.originFromAnchorTransform was highly unreliable to indicate where the anchor was and how it was oriented, so we access the geometry data instead.
    var avergeNormal: simd_float3 {
        let normalsArray = normals.asSIMD3(ofType: Float.self)
        
        return acceleratedAverage(normalsArray)
    }
    
    var avergePosition: simd_float3 {
        let verticesArray = vertices.asSIMD3(ofType: Float.self)
        
        return acceleratedAverage(verticesArray)
    }
    
    private func acceleratedAverage(_ vectors: [simd_float3]) -> simd_float3 {
        
        // Prevent divide by zero
        let epsilon: Float = 0.000_001
        
        // Separate the components
        //!! not sure if near 0 is a suitable replacement for nan...
        let xComponents = vectors.map { $0.x.isNaN ? epsilon : $0.x }
        let yComponents = vectors.map { $0.y.isNaN ? epsilon : $0.y }
        let zComponents = vectors.map { $0.z.isNaN ? epsilon : $0.z }
        
        let length = vDSP_Length(xComponents.count)
        
        let stride = vDSP_Stride(1)
        
        // Function to calculate the mean using vDSP
        func mean(of array: [Float]) -> Float {
            var mean: Float = .nan
            vDSP_meanv(array, stride, &mean, length)
            return mean
        }
        
        // Calculate the mean of each component
        let meanX = mean(of: xComponents)
        let meanY = mean(of: yComponents)
        let meanZ = mean(of: zComponents)
        
        // Combine the means into a single simd_float3
        return simd_float3(meanX, meanY, meanZ)
    }
}
