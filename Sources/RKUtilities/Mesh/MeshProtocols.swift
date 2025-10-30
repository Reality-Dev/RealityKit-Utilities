import ARKit
import RealityKit

#if os(visionOS)
// MARK: - Protocol Conformance visionOS

extension MeshAnchor.MeshClassification: MeshClassification {}

extension MeshAnchor.Geometry: MeshGeometry {
    public typealias Source = GeometrySource
    /// To get the mesh's classification, the sample app parses the classification's raw data and instantiates an
    /// `ARMeshClassification` object. For efficiency, ARKit stores classifications in a Metal buffer in `ARMeshGeometry`.
    func classificationOf(faceWithIndex index: Int) -> MeshAnchor.MeshClassification {
        classificationOf(faceWithIndex: index, of: MeshAnchor.MeshClassification.self) ?? .none
    }
}

extension GeometrySource: GeometricSource {}

extension GeometryElement: GeometricElement {
    
    public var vertexCountPerFace: Int {
        primitive.indexCount
    }
}

extension PlaneAnchor.Geometry.Extent: PlaneExtent {}

extension PlaneAnchor.Geometry: PlaneGeometry {
    
    public typealias IndexType = Int // Assuming GeometryElement’s indices are `Int`
    
    public var vertices: [simd_float3] {
        // Assuming `meshVertices` provides data in a format convertible to `[simd_float3]`
        meshVertices.asSIMD3(ofType: Float.self)
    }
    
    public var vertexCountPerFace: Int {
        meshFaces.primitive.indexCount
    }
    
    public var faceCount: Int {
        meshFaces.count
    }
    
    public var faceIndices32: [UInt32] {
        (0..<faceCount * vertexCountPerFace).map {
            meshFaces.buffer.contents()
                .advanced(by: $0 * meshFaces.bytesPerIndex)
            //!! Is this correct or is it UInt16??
                .assumingMemoryBound(to: UInt32.self).pointee
        }
    }
    public var faceIndices16: [UInt16] {
        faceIndices32.map{UInt16($0)}
    }
}

#elseif os(iOS)

// MARK: - Protocol Conformance iOS

extension ARMeshGeometry: MeshGeometry {
    
    public typealias Source = ARGeometrySource
    // !! Potential performance cost with existential type (any Keyword).
    // Use Generics instead.
    public var classifications: ARGeometrySource? {
        return classification
    }
    /// To get the mesh's classification, the sample app parses the classification's raw data and instantiates an
    /// `ARMeshClassification` object. For efficiency, ARKit stores classifications in a Metal buffer in `ARMeshGeometry`.
    func classificationOf(faceWithIndex index: Int) -> ARMeshClassification {
        classificationOf(faceWithIndex: index, of: ARMeshClassification.self) ?? .none
    }
}

extension ARMeshClassification: MeshClassification {}

extension ARGeometrySource: GeometricSource {}

extension ARGeometryElement: GeometricElement {
    public var vertexCountPerFace: Int {
        indexCountPerPrimitive
    }
}

@available(iOS 16.0, *)
extension ARPlaneExtent: PlaneExtent {}

extension ARPlaneGeometry: PlaneGeometry {
    
    public var vertexCountPerFace: Int {3}
    
    public var faceCount: Int {
        triangleCount
    }
    
    public var faceIndices32: [UInt32] {
        triangleIndices.map{UInt32($0)}
    }
    public var faceIndices16: [UInt16] {
        triangleIndices.map{UInt16($0)}
    }
}

#endif
// MARK: - Protocols

public protocol PlaneGeometry {
    /// An array of vertex positions describing the plane mesh
    var vertices: [simd_float3] { get }
    
    var vertexCountPerFace: Int { get }
    
    var faceCount: Int { get }
    
    var faceIndices32: [UInt32] { get }
    
    var faceIndices16: [UInt16] { get }
}

public protocol PlaneExtent {
    /// The width of the plane
    var width: Float { get }
    
    /// The height of the plane
    var height: Float { get }
}

public protocol MeshGeometry {
    /// The type representing the geometry source for vertices, normals, and classifications
    associatedtype Source: GeometricSource
    
    /// The type representing the geometry element for faces
    associatedtype Element: GeometricElement
    
    /// The vertices of the mesh
    var vertices: Source { get }
    
    /// The faces of the mesh
    var faces: Element { get }
    
    /// The normals of the mesh, representing direction information for each face
    var normals: Source { get }
    
    /// The classification of each face in the mesh (optional)
    var classifications: Source? { get }
}

public protocol MeshClassification: RawRepresentable where RawValue == Int {}

public protocol GeometricSource {
    /// A Metal buffer containing vector data
    var buffer: any MTLBuffer { get }
    
    /// The number of scalar components in each vector
    var componentsPerVector: Int { get }
    
    /// The number of vectors in the buffer
    var count: Int { get }
    
    /// The format of vector data in the buffer
    var format: MTLVertexFormat { get }
    
    /// The offset, in bytes, from the beginning of the buffer
    var offset: Int { get }
    
    /// The length, in bytes, from the start of one vector in the buffer to the start of the next vector
    var stride: Int { get }
}

public
extension GeometricSource {
    func asArray<T>(ofType: T.Type) -> [T] {
        //!! Needs to be on main?
        assert(MemoryLayout<T>.stride == stride, "Invalid stride \(MemoryLayout<T>.stride); expected \(stride)")
        return (0..<self.count).map {
            buffer.contents().advanced(by: offset + stride * Int($0)).assumingMemoryBound(to: T.self).pointee
        }
    }
    
    // SIMD3 has the same storage as SIMD4.
    func asSIMD3<T>(ofType: T.Type) -> [SIMD3<T>] {
        return asArray(ofType: (T, T, T).self).map { .init($0.0, $0.1, $0.2) }
    }
}

public protocol GeometricElement  {
    /// A Metal buffer containing primitive data
    var buffer: any MTLBuffer { get }
    
    /// The number of bytes for each index
    var bytesPerIndex: Int { get }
    
    /// The number of primitives in the buffer
    var count: Int { get }
    
    var vertexCountPerFace: Int { get }
}
