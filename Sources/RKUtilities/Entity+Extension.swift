/*
See the LICENSE file and the LICENSE ORIGINS folder for this sample’s licensing information.
 */

import RealityKit

// MARK: - Entity extensions
public extension Entity {
    
    func visit(using block: (Entity) -> Void) {
        block(self)
        for child in children {
            child.visit(using: block)
        }
    }
        
    func modifyMaterials(_ closure: (RealityKit.Material) throws -> RealityKit.Material) rethrows {
        try children.forEach { try $0.modifyMaterials(closure) }

        guard var comp = components[ModelComponent.self] as? ModelComponent else { return }
        comp.materials = try comp.materials.map { try closure($0) }
        components[ModelComponent.self] = comp
    }

    @available(iOS 15.0, macOS 12.0, *)
    func set(_ modifier: CustomMaterial.GeometryModifier) throws {
        try modifyMaterials { try CustomMaterial(from: $0, geometryModifier: modifier) }
    }

    @available(iOS 14.0, macOS 11.0, *)
    func attachDebugModelComponent(_ debugModel: ModelDebugOptionsComponent) {
        components.set(debugModel)
        children.forEach { $0.attachDebugModelComponent(debugModel) }
    }

    @available(iOS 15.0, macOS 11.0, *)
    func removeDebugModelComponent() {
        components[ModelDebugOptionsComponent.self] = nil
        children.forEach { $0.removeDebugModelComponent() }
    }
}
