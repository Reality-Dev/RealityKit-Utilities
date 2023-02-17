/*
See the LICENSE file and the LICENSE ORIGINS folder for this sample’s licensing information.
 */

import RealityKit

#if canImport(ARKit)
import ARKit

// MARK: - ARPlaneAnchor extensions
extension ARPlaneAnchor {
    func correspondingAnchorEntity(scene: Scene) -> AnchorEntity? {
        return scene.anchors.first(where: {$0.anchorIdentifier == self.identifier}) as? AnchorEntity
    }
}

// MARK: - AnchorEntity extensions
public extension AnchorEntity {
    func correspondingARPlaneAnchor(session: ARSession) -> ARAnchor? {
        return session.currentFrame?.anchors.first(where: {$0.identifier == self.anchorIdentifier})
    }
}

// MARK: - ARView extensions
public extension ARView {
    /// This performs a raycast from the given screen point.
    /// - Parameters:
    ///   - point: The screen-space point from which to raycast into the scene.
    ///   - alignment: The target alignment for the raycast query (with respect to gravity). A raycast ignores potential targets with an alignment different than the one you specify in the raycast query.
    /// - Returns: An ARRaycastResult: Information about a real-world surface found by examining a point on the screen.
    func smartRaycast(from point: CGPoint,
                      alignment: ARRaycastQuery.TargetAlignment = .any) -> ARRaycastResult? {
        
        // Perform the raycast.
        guard let existingPlaneQuery = self.makeRaycastQuery(from: point,
                                                             allowing: .existingPlaneGeometry,
                                                             alignment: alignment)
        else {return nil}
        
        
        let results = self.session.raycast(existingPlaneQuery)
        
        // Check for a result on an existing plane geometry.
        if let existingPlaneGeometryResult = results.first(where: { $0.target == .existingPlaneGeometry }) {
            return existingPlaneGeometryResult
        }
        
        //As a primary fallback, look for results on estimated planes.
        //If the device has LiDAR, then this will intersect with the LiDAR scene mesh.
            guard let estimatedPlaneQuery = self.makeRaycastQuery(from: point,
                                                                  allowing: .estimatedPlane,
                                                                  alignment: alignment) else {return nil}
            if let estimatedPlaneResult = self.session.raycast(estimatedPlaneQuery).first {
                return estimatedPlaneResult
            }
        
        //As a secondary fallback, look for results on infinite horizontal planes.
        guard let infinitePlaneQuery = self.makeRaycastQuery(from: point,
                                                             allowing: .existingPlaneInfinite,
                                                             alignment: .horizontal) else {return nil}
        
        if let infinitePlaneResult = self.session.raycast(infinitePlaneQuery).first {
                return infinitePlaneResult
        }
        
        return nil
    }
}
#endif


// MARK: - Entity extensions
public extension Entity {

    func extents(includingInactive: Bool = true) -> simd_float3 {
        return self.visualBounds(recursive: true, relativeTo: nil, excludeInactive: !includingInactive).extents
    }
    
    ///There can only be up to one of each type of component in the Entity's ComponentSet.
    func component<T: Component>(forType: T.Type) -> T? {
        return self.components[T.self] as? T
    }
    
    ///Components are value types so we must re-set them on the Entity every time they are modified. This method takes care of re-setting them for us.
    func modifyComponent<T: Component>(forType: T.Type, _ closure: ( inout T) -> Void) {
        
        guard var component = component(forType: T.self) else { return }
        closure(&component)
        components[T.self] = component
    }
    
    var modelComponent: ModelComponent? {
        get {
            return self.component(forType: ModelComponent.self)
        } set {
            self.components[ModelComponent.self] = newValue
        }
    }
    ///The Entity's transform in world space. That is, relative to `nil`.
    ///- Use `worldTransform.matrix` to get the transform in the form of a 4x4 matrix.
    var worldTransform: Transform {
        return self.convert(transform: .init(), to: nil)
    }
    
    ///The Entity's position in world space. That is, relative to `nil`.
    var worldPosition: simd_float3 {
        get {
            self.position(relativeTo: nil)
        }
        set {
            self.setPosition(newValue, relativeTo: nil)
        }
    }
    
    func resetAllTransforms(){
        self.visit(using: {$0.setTransformMatrix(float4x4.init(diagonal: [1,1,1,1]), relativeTo: self.parent)})
    }
    
    ///Recursively searches (depth first) through all levels of parents for an Entity that satisfies the given predicate.
    func findAncestor(where predicate: (Entity) -> Bool) -> Entity? {
        guard let parent = parent else {return nil}
        if predicate(parent) { return parent}
        else { return parent.findAncestor(where: predicate) }
    }
    
    ///Recursively searches (depth first) through self and all descendants for an Entity that satisfies the given predicate, Not just through the direct children.
    func findEntity(where predicate: (Entity) -> Bool) -> Entity? {
        if predicate(self) {return self}
        for child in self.children {
            if let satisfier = child.findEntity(where: predicate) {return satisfier}
        }
        return nil
    }
    
    ///Recursively searches through self and all descendants for Entities that satisfy the given predicate, Not just through the direct children.
    func findEntities(where predicate: (Entity) -> Bool) -> [Entity] {
        var satisfyingEntities = [Entity]()
        if predicate(self) { satisfyingEntities.append(self) }
        for child in self.children {
            satisfyingEntities.append(contentsOf: child.findEntities(where: predicate))
        }
        return satisfyingEntities
    }
    
    ///Recursively searches (depth first) through each entity and its descendants in the given array for an Entity that satisfies the given predicate and returns the first one that is found.
    static func findEntity(from entArray: [Entity], where predicate: (Entity) -> Bool) -> Entity? {
        for parentEnt in entArray {
            if let satisfyingEnt = parentEnt.findEntity(where: predicate) {
                return satisfyingEnt
            }
        }
        return nil
    }
    
    ///Recursively searches through all descendants, depth first, for an Entity with a Model Component, Not just through the direct children.
    ///
    ///Returns the first model entity it finds.
    ///Returns the orginal entity that called this method if it is a model entity.
    func findFirstHasModelComponent() -> Entity? {
        return findEntity(where: {$0.components.has(ModelComponent.self)})
    }
    
    ///Recursively searches through all descendants, depth first, for Entities with a Model Component, Not just through the direct children.
    ///
    ///Returns all Entities it finds that have a Model Component.
    ///The returned array includes the original entity that called this method if it is a model entity.
    func findAllHasModelComponent() -> [Entity] {
        return findEntities(where: {$0.components.has(ModelComponent.self)})
    }
    
    ///Remove synchronization component to save memory when Not in a synchronized session.
    func removeSynchronization(){
        visit {
            $0.components.remove(SynchronizationComponent.self)
        }
    }
    
    static func makeSphere(color: SimpleMaterial.Color = .blue,
                            radius: Float = 0.05,
                            isMetallic: Bool = true) -> ModelEntity {
        
        let sphereMesh = MeshResource.generateSphere(radius: radius)
        let sphereMaterial = SimpleMaterial.init(color: color, isMetallic: isMetallic)
        return ModelEntity(mesh: sphereMesh, materials: [sphereMaterial])
    }
    static func makeBox(color: SimpleMaterial.Color = .blue,
                           size: simd_float3 = .one,
                            isMetallic: Bool = true) -> ModelEntity {
        
        let boxMesh = MeshResource.generateBox(size: size)
        let boxMaterial = SimpleMaterial.init(color: color, isMetallic: isMetallic)
        return ModelEntity(mesh: boxMesh, materials: [boxMaterial])
    }
    
    ///Recursively prints all children names and how many available animations they have.
    func printAnimations(){
        printAnimations(spacing: "")
    }
    private func printAnimations(spacing: String){
        print(spacing, self.name, "Available animations:", self.availableAnimations.count)
        //Use indentation to make the hierarchy easier to visualize.
        let extendedSpacing = spacing + " "
        for child in self.children {
            child.printAnimations(spacing: extendedSpacing)
        }
    }
    
    ///Returns the first entity in the hierarchy that has an available animation, searching the entire hierarchy recursively.
    func findAnim() -> Entity? {
        return findEntity(where: {$0.availableAnimations.isEmpty == false})
    }
    
    ///The x-rotation value of the entity, in radians.
    var xRotation: Float {
        //Extract the x-rotation value from the quaternion in radians.
        get {
            //Convert the value of the child's upward vector to its parent's coordinate space so we can compare this with the parent's upward vector later on.
            var upward = self.convert(position: [0,0,-1], to: self.parent)
            //Place the vector in the 2D Y-Z plane. i.e. Flatten it.
            upward.x = 0
            //Make the vector of length 1.
            upward = normalize(upward)
            //Compare the parent's upward vector with the flattened child's upward vector and extract the angle.
            let yAngle = acos(dot([0,0,-1], upward))
            return yAngle
        }
    }
    
        ///The y-rotation value of the entity, in radians.
        var yRotation: Float {
            //Extract the y-rotation value from the quaternion in radians.
            get {
                //Convert the value of the child's forward vector to its parent's coordinate space so we can compare this with the parent's forward vector later on.
                var forward = self.convert(position: [0,0,-1], to: self.parent)
                //Place the vector in the 2D X-Z plane. i.e. Flatten it.
                forward.y = 0
                //Make the vector of length 1.
                forward = normalize(forward)
                //Compare the parent's forward vector with the flattened child's forward vector and extract the angle.
                let yAngle = acos(dot([0,0,-1], forward))
                return yAngle
            }
        }
    
    ///The z-rotation value of the entity, in radians.
    var zRotation: Float {
        //Extract the z-rotation value from the quaternion in radians.
        get {
            //Convert the value of the child's upward vector to its parent's coordinate space so we can compare this with the parent's upward vector later on.
            var upward = self.convert(position: [0,1,0], to: self.parent)
            //Place the vector in the 2D X-Y plane. i.e. Flatten it.
            upward.z = 0
            //Make the vector of length 1.
            upward = normalize(upward)
            //Compare the parent's upward vector with the flattened child's upward vector and extract the angle.
            let yAngle = acos(dot([0,1,0], upward))
            return yAngle
        }
    }
}

// MARK: - simd_float3 extensions
//This is the same type as SIMD3<Float>
public extension simd_float3 {
    func smoothed(oldVal: simd_float3, amount smoothingAmount: Float) -> simd_float3 {
        let smoothingAmount = smoothingAmount.clamped(0, 1)
        return (oldVal * smoothingAmount) + (self * ( 1 - smoothingAmount))
    }
        
    static var pitch: simd_float3 = [1, 0, 0]
    
    static var yaw: simd_float3 = [0, 1, 0]
    
    static var roll: simd_float3 = [0, 0, 1]
    
    static var up: simd_float3 = [0, 1, 0]
    
    static var forward: simd_float3 = [0, 0, -1]
    
    var avg: Float {
        return Float.avg(self.x, self.y, self.z)
    }
    
    var max: Float {
        return Swift.max(self.x, self.y, self.z)
    }
    
    func maxLength(_ maxLength: Float) -> simd_float3 {
        let currentLength = length(self)
        if currentLength > maxLength {
            return self * (maxLength / currentLength)
        }
        return self
    }
    func minLength(_ minLength: Float) -> simd_float3 {
        let currentLength = length(self)
        if currentLength < minLength {
            return self * (minLength / currentLength)
        }
        return self
    }
    
    func toLength(_ newLength: Float) -> simd_float3 {
        let currentLength = length(self)
        return self * (newLength / currentLength)
    }
    
    ///Elementwise minimum of all input vectors. Each component of the result is the smallest of the corresponding component of the inputs.
    static func min(inputs: [simd_float3]) -> simd_float3 {
        let x = inputs.map{$0.x}.min() ?? 0.0
        let y = inputs.map{$0.y}.min() ?? 0.0
        let z = inputs.map{$0.z}.min() ?? 0.0
        return [x,y,z]
    }
    
    ///Elementwise maximum of all input vectors. Each component of the result is the largest of the corresponding component of the inputs.
    static func max(inputs: [simd_float3]) -> simd_float3 {
        let x = inputs.map{$0.x}.max() ?? 0.0
        let y = inputs.map{$0.y}.max() ?? 0.0
        let z = inputs.map{$0.z}.max() ?? 0.0
        return [x,y,z]
    }
}

// MARK: - Comparable extensions
public extension Comparable {
    
    /// Returns self clamped between two values.
    /// - If self is already between the two input values, returns self. If self is below a, returns a. If self is above b, returns b.
    /// - Parameters:
    ///   - a: The lower bound
    ///   - b: The upper bound.
    /// - Returns: self clamped between the two input values.
    func clamped(_ a: Self, _ b: Self) -> Self {
        min(max(self, a), b)
    }
}

