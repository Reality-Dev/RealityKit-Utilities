//
//  File.swift
//  
//
//  Created by Grant Jarvis on 12/30/23.
//

import RealityKit

// Would use a protocol but to be accessible to all targets, the protocol and all of its properties and methods must be public as well, and we do not want isRegistered to be publicly set-able.
public struct Registerer {
    private static var registeredComponents = Set<String>()
    
    public static func register<T>(_ componentType: T.Type) where T: Component {
        let description = String(describing: componentType)
        
        guard registeredComponents.contains(description) == false else {return}
        
        // Call the registerComponent() method ONLY ONCE for every custom component type that you use in your app before you use it.
        componentType.registerComponent()
        
        registeredComponents.insert(description)
    }
}
