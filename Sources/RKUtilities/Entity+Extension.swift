/*
See the LICENSE file and the LICENSE ORIGINS folder for this sample’s licensing information.
 */

import RealityKit
import CoreMedia

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

// MARK: - Entity extensions
public extension Entity {
    
    func visit(using block: (Entity) -> Void) {
        block(self)
        for child in children {
            child.visit(using: block)
        }
    }
    
    func extents(includingInactive: Bool = true,
                 relativeTo referenceEntity: Entity? = nil) -> simd_float3 {
        return self.visualBounds(recursive: true, relativeTo: referenceEntity, excludeInactive: !includingInactive).extents
    }
    
    /*
     Example Usage:
     
     let modelComp = self.component(forType: ModelComponent.self)
     */
    ///There can only be up to one of each type of component in the Entity's ComponentSet.
    func component<T: Component>(forType: T.Type) -> T? {
#if os(visionOS)
        return components[T.self]
#else
        if #available(iOS 18.0, *) {
            // Typecasting not required iOS 18.0+
            return components[T.self]
        } else {
            // Fixes compiler warning.
            return (components[T.self] as Any) as? T
        }
#endif
    }
    
    /*
     Example Usage:
     
     myEntity.modifyComponent(forType: ModelComponent.self){
         $0.materials = $0.materials.map({$0.setOpacity(0.5)})
     }
     */
    ///Components are value types so we must re-set them on the Entity every time they are modified. This method takes care of re-setting them for us.
    func modifyComponent<T: Component>(forType: T.Type, _ closure: ( inout T) -> Void) {
        
        guard var component = component(forType: T.self) else { return }
        closure(&component)
        components[T.self] = component
    }
    
    var modelComponent: ModelComponent? {
        get { component(forType: ModelComponent.self) }
        set { components[ModelComponent.self] = newValue }
    }
    
    var physicsBodyComponent: PhysicsBodyComponent? {
        get { component(forType: PhysicsBodyComponent.self) }
        set { components[PhysicsBodyComponent.self] = newValue }
    }
    
    /// Property for getting or setting an entity's `CollisionComponent`.
    var collisionComponent: CollisionComponent? {
        get { component(forType: CollisionComponent.self) }
        set { components[CollisionComponent.self] = newValue }
    }
    
    ///The Entity's transform in world space. That is, relative to `nil`.
    ///- Use `worldTransform.matrix` to get the transform in the form of a 4x4 matrix.
    var worldTransform: Transform {
        return self.convert(transform: .init(), to: nil)
    }
    
    ///The Entity's position (a.k.a translation) in world space. That is, relative to `nil`.
    var worldPosition: simd_float3 {
        get {
            self.position(relativeTo: nil)
        }
        set {
            self.setPosition(newValue, relativeTo: nil)
        }
    }
    
    ///The Entity's scale in world space. That is, relative to `nil`.
    var worldScale: simd_float3 {
        get {
            return scale(relativeTo: nil)
        }
        set {
            self.setScale(newValue, relativeTo: nil)
        }
    }
    
    ///The Entity's rotation (a.k.a orientation) in world space. That is, relative to `nil`.
    var worldRotation: simd_quatf {
        get {
            return orientation(relativeTo: nil)
        }
        set {
            self.setOrientation(newValue, relativeTo: nil)
        }
    }
    
    func resetAllTransforms(){
        self.visit(using: {$0.setTransformMatrix(float4x4.init(diagonal: [1,1,1,1]), relativeTo: self.parent)})
    }
    
#if !os(visionOS)
    func isOnScreen(
        arView: ARView,
        bounds: CGRect,
        margins: CGSize = .zero
    ) -> Bool {
        guard let screenPosition = arView.project(self.worldPosition) else {
            return false
        }
        let width = (0 + margins.width) ... (bounds.width - margins.width)
        let height = (0 + margins.height) ... (bounds.height - margins.height)
        let inBounds = width.contains(screenPosition.x) && height.contains(screenPosition.y)
        return inBounds
    }
#endif
    
    func findInRoot(where predicate: (Entity) -> Bool) -> Entity? {
        guard let root = findAncestor(where: {$0.parent == nil}) else {return nil}
        
        return root.findEntity(where: predicate)
    }
    
    ///Recursively searches (depth first) through all levels of parents for an Entity that satisfies the given predicate.
    func findAncestor(where predicate: (Entity) -> Bool) -> Entity? {
        guard let parent = parent else {return nil}
        if predicate(parent) { return parent}
        else { return parent.findAncestor(where: predicate) }
    }
    
    ///Recursively searches (depth first) through all levels of parents for an Entity that satisfies the given predicate.
    func findAncestorOrSelf(where predicate: (Entity) -> Bool) -> Entity? {
        if predicate(self) {return self}
        else {return parent?.findAncestorOrSelf(where: predicate)}
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
    static func makePlane(color: SimpleMaterial.Color = .blue,
                          isMetallic: Bool = true,
                          width: Float = 1,
                          height: Float = 1,
                          cornerRadius: Float = 0) -> ModelEntity
    {
        let planeMesh = MeshResource.generatePlane(width: width, height: height, cornerRadius: cornerRadius)
        let planeMaterial = SimpleMaterial(color: color, isMetallic: isMetallic)
        return ModelEntity(mesh: planeMesh,
                           materials: [planeMaterial])
    }
    
    ///Returns the first entity in the hierarchy that has an available animation, searching the entire hierarchy recursively.
    func findAnim() -> Entity? {
        return findEntity(where: {$0.availableAnimations.isEmpty == false})
    }
    
    ///Find the first descendant (or this entity if it has a(n) animation(s)) with an animation and play it.
    ///
    ///IMPORTANT: Does not work with a loaded `ModelEntity`, only works when loading a file as an `Entity`.
    @available(macOS 12.0, iOS 15.0, *)
    @discardableResult func playFirstAnimation(transitionDuration: TimeInterval = 0,
                                               blendLayerOffset: Int = 0,
                                               separateAnimatedValue: Bool = false,
                                               startsPaused: Bool = false,
                                               clock: CMClockOrTimebase? = nil) -> AnimationPlaybackController?
    {
        guard let animEntity = findAnim() else { return nil }
        let animation = animEntity.availableAnimations[0].repeat(duration: .infinity)
        return animEntity.playAnimation(animation,
                             transitionDuration: transitionDuration,
                             blendLayerOffset: blendLayerOffset,
                             separateAnimatedValue: separateAnimatedValue,
                             startsPaused: startsPaused,
                             clock: clock)
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
    
    enum TransformElement: String {
        case position
        case scale
        case rotation
        case all
    }
    func printTransform(for element: TransformElement){
        printTransform(for: element, spacing: "")
    }
    private func printTransform(for element: TransformElement, spacing: String) {
        var printableLocal: Any
        var printableWorld: Any
        switch element {
        case .position:
            printableLocal = self.position
            printableWorld = self.position(relativeTo: nil)
        case .scale:
            printableLocal = self.scale
            printableWorld = self.scale(relativeTo: nil)
        case .rotation:
            printableLocal = self.orientation
            printableWorld = self.orientation(relativeTo: nil)
        case .all:
            printableLocal = self.transform
            printableWorld = self.convert(transform: .init(), to: nil)
        }
        print(spacing, self.name, "local \(element.rawValue)", printableLocal)
        print(spacing, self.name, "world \(element.rawValue)", printableWorld)
        children.forEach {$0.printTransform(for: element, spacing: spacing + "  ")}
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
            let xAngle = acos(dot([0,0,-1], upward))
            return xAngle.isNaN ? 0 : xAngle
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
                return yAngle.isNaN ? 0 : yAngle
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
            let zAngle = acos(dot([0,1,0], upward))
            return zAngle.isNaN ? 0 : zAngle
        }
    }
}
