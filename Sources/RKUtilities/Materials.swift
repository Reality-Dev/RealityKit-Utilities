/*
See the LICENSE file and the LICENSE ORIGINS folder for this sample’s licensing information.
 */

import RealityKit
import Metal

//MARK: - Entity extensions
public extension Entity {

    ///Getting this Float does not take into account any opacity texture that may be set on the material, only the scale, but setting it will preserve any texture that may be present.
    /// - If multiple materials are present on this Entity, then the average opacity scale of the materials is returned.
    /// - This will NOT set the opacity on any descendant entities. If you would like to recursively set opacity, use `Entity.visit{ $0.opacity = newValue }`
    @available(iOS 15.0, macOS 12.0, *)
    var opacity: Float {
        get {
            guard let modelComp = self.modelComponent else {return 1.0}
            let opacityScales = modelComp.materials.map({($0 as? HasOpacity)?._opacity ?? 1.0})
            return Float.avg(opacityScales)
        }
        set {
            self.modifyComponent(forType: ModelComponent.self){
                $0.materials = $0.materials.map({$0.setOpacity(newValue)})
            }
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

//MARK: - Material extensions

public protocol HasOpacity: Material {
    ///Getting this Float does not take into account any opacity texture that may be set on the material, only the scale, but setting it will preserve any texture that may be present.
    var _opacity: Float {get set}
}

@available(iOS 15.0, macOS 12.0, *)
extension PhysicallyBasedMaterial: HasOpacity {
    public var _opacity: Float {
        get {
            return self.blending.opacity
        }
        set {
            self.blending.opacity = newValue
        }
    }
}

//UnlitMaterial.Blending is a typealias for PhysicallyBasedMaterial.Blending, so we do not need to copy the code twice.
@available(iOS 15.0, macOS 12.0, *)
extension UnlitMaterial: HasOpacity {
    public var _opacity: Float {
        get {
            return self.blending.opacity
        }
        set {
            self.blending.opacity = newValue
        }
    }
}
@available(iOS 15.0, macOS 12.0, *)
public extension PhysicallyBasedMaterial.Blending {
    var opacity: Float {
        get {
            switch self {
            case .opaque:
                return 1.0
            case .transparent(opacity: let opacity):
                return opacity.scale
            @unknown default:
                return 1.0
            }
        }
        set {
            if newValue == 1.0 {
                self = .opaque
            } else {
                switch self {
                case .opaque:
                    self = .transparent(opacity: .init(floatLiteral: newValue))
                case .transparent(opacity: let opacity):
                    self = .transparent(opacity: .init(scale: newValue, texture: opacity.texture))
                @unknown default:
                    self = .transparent(opacity: .init(floatLiteral: newValue))
                }
            }
        }
    }
}

//We could initialize a CustomMaterial.Blending from a PhysicallyBasedMaterial.Blending and re-use the same code, but we duplicate it here to save the performance cost of initialization, which may be especially useful in cases such as opacity animations.
@available(iOS 15.0, macOS 12.0, *)
extension CustomMaterial: HasOpacity {
    public var _opacity: Float {
        get {
            return self.blending.opacity
        }
        set {
            self.blending.opacity = newValue
        }
    }
    init?(surfaceShaderName: String,
          geometryModifier: CustomMaterial.GeometryModifier? = nil,
          lightingModel: CustomMaterial.LightingModel = .lit,
          library: MTLLibrary
    ) {
        
        let surfaceShader = CustomMaterial.SurfaceShader(
            named: surfaceShaderName,
            in: library
        )

        do {
            try self.init(surfaceShader: surfaceShader,
                                  geometryModifier: geometryModifier,
                          lightingModel: lightingModel)
        } catch {
            print(error)
            return nil
        }
    }
}
@available(iOS 15.0, macOS 12.0, *)
public extension CustomMaterial.Blending {
    var opacity: Float {
        get {
            switch self {
            case .opaque:
                return 1.0
            case .transparent(opacity: let opacity):
                return opacity.scale
            @unknown default:
                return 1.0
            }
        }
        set {
            if newValue == 1.0 {
                self = .opaque
            } else {
                switch self {
                case .opaque:
                    self = .transparent(opacity: .init(floatLiteral: newValue))
                case .transparent(opacity: let opacity):
                    self = .transparent(opacity: .init(scale: newValue, texture: opacity.texture))
                @unknown default:
                    self = .transparent(opacity: .init(floatLiteral: newValue))
                }
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
public extension RealityKit.Material {
    
    ///Getting this Float does not take into account any opacity texture that may be set on the material, only the scale, but setting it will preserve any texture that may be present.
    var opacity: Float {
        get {
            if let hasOpacity = self as? HasOpacity {
                return hasOpacity._opacity
            } else {
                return 1.0
            }
        }
    }
    func setOpacity(_ newValue: Float) -> RealityKit.Material {
        guard var hasOpacity = self as? HasOpacity else {return self}
        
        hasOpacity._opacity = newValue
        
        return hasOpacity
    }
    
    var isOpaque: Bool {
        return self.opacity > 0.995
    }
}
