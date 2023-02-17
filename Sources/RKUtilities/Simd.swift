/*
See LICENSE folder for this sample’s licensing information.
 */

import simd
import RealityKit

//MARK: - Float extensions
public extension Float {
    
    static func avg(_ inputs: [Float]) -> Float {
        let sum = inputs.reduce(0, +)

        return sum / Float(inputs.count)
    }
    
    static func avg(_ inputs: Float...) -> Float {
        return avg(inputs)
    }
    
    var sign: Float {
        if self < 0 {
            return -1
        } else {
            return 1
        }
    }
    
    /// Return the constant needed to convert degrees to radians
    static let degreesToRadians: Float = (.pi / 180)

    /// Return the linear interpolation between two values at supplied "progress"
    static func lerp(_ value1: Float, _ value2: Float, progress: Float) -> Float {
        return value1 + ((value2 - value1) * progress)
    }

    /// Returns the "progress" value that yields the lerp output value within the range [value1, value2]
    static func inverseLerp(_ value1: Float, _ value2: Float, lerpOutput: Float) -> Float {
        var delta = value2 - value1
        if delta == 0.0 {
            print("Preventing divide by zero.")
            delta = 1.0
        }
        return (lerpOutput - value1) / delta
    }

    var dotTwoDescription: String { String(format: "%0.2f", self) }
}

//MARK: - simd_float2 extensions
public extension SIMD2 where Scalar == Float {
    /// Returns the magnitude of the two points that comprise the 2d Vector
    func magnitude() -> Float {
        return sqrtf(x * x + y * y)
    }

    var terseDescription: String { "\(x), \(y)" }
    var dotFourDescription: String { String(format: "(%0.4f, %0.4f)", x, y) }
    var dotTwoDescription: String { String(format: "(%0.2f, %0.2f)", x, y) }
    var fiveDotTwoDescription: String { String(format: "(%5.2f, %5.2f)", x, y) }
}

//MARK: - simd_float3 extensions
public extension SIMD3 where Scalar == Float {
    /// Determine if the vector is pointing somewhat upward in 3d space.
    /// -  Threshold for upwardness expressed as a constant value
    func isUpwardPointing() -> Bool {
        let thresholdForUpwardPointingAngle = Float.pi / 8
        let thetaOffset = simd.acos(normalize(self).y)
        return thetaOffset <= thresholdForUpwardPointingAngle
    }

    var terseDescription: String { "\(x), \(y), \(z)" }
    var dotFourDescription: String { String(format: "(%0.4f, %0.4f, %0.4f)", x, y, z) }
    var dotTwoDescription: String { String(format: "(%0.2f, %0.2f, %0.2f)", x, y, z) }
    var fiveDotTwoDescription: String { String(format: "(%5.2f, %5.2f, %5.2f)", x, y, z) }
}

//MARK: - simd_float4 extensions
public extension SIMD4 where Scalar == Float {
    
    init(_ xyz: SIMD3<Float>, w: Float) {
        self.init(xyz.x, xyz.y, xyz.z, w)
    }

    var xyz: SIMD3<Float> {
        get { return SIMD3<Float>(x: x, y: y, z: z) }
        set {
            x = newValue.x
            y = newValue.y
            z = newValue.z
        }
    }

    /// Determine if the vector is pointing somewhat upward in 3d space.
    /// -  Threshold for upwardness expressed as a constant value
    func isUpwardPointing() -> Bool {
        let thresholdForUpwardPointingAngle = Float.pi / 8
        let thetaOffset = simd.acos(normalize(self.xyz).y)
        return thetaOffset <= thresholdForUpwardPointingAngle
    }

    var terseDescription: String { "\(x), \(y), \(z), \(z)" }
    var dotFourDescription: String { String(format: "(%0.4f, %0.4f, %0.4f, %0.4f)", x, y, z, w) }
    var dotTwoDescription: String { String(format: "(%0.2f, %0.2f, %0.2f, %0.2f)", x, y, z, w) }
    var fiveDotTwoDescription: String { String(format: "(%5.2f, %5.2f, %5.2f, %5.2f)", x, y, z, w) }
}

//MARK: - simd_quatf extensions
public extension simd_quatf {
    
    /// Returns a new quaternion representing only the Y-Axis rotation of the original Quaternion
    func yaw() -> simd_quatf {
        var quat = self
        quat.vector[0] = 0
        quat.vector[2] = 0
        let mag = sqrt(quat.vector[3] * quat.vector[3] + quat.vector[1] * quat.vector[1])
        // Magnitude is always positive.
        if mag > 0 {
            quat.vector[3] /= mag
            quat.vector[1] /= mag
        }
        return quat
    }
    
    /// The identity quaternion
    static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
}
//MARK: - float4x4 extensions
public extension float4x4 {
  /**
  Treats matrix as a (right-hand column-major convention) transform matrix
  and factors out the translation component of the transform.
  */
  var translation: SIMD3<Float> {
    get {
      let translation = columns.3
      return SIMD3<Float>(translation.x, translation.y, translation.z)
    }
    set(newValue) {
      columns.3 = SIMD4<Float>(newValue.x, newValue.y, newValue.z, columns.3.w)
    }
  }

    /**
    Factors out the orientation component of the transform.
    */
    var orientation: simd_quatf {
        get {
            var localMatrix = self
            localMatrix.scale = .one
            return simd_quaternion(localMatrix)
        }
        set {
            let translationMatrix = simd_float4x4(translation: translation)
            let rotationMatrix = matrix_float4x4(newValue)
            let scaleMatrix = simd_float4x4(scale: scale)
            self = simd_mul(simd_mul(translationMatrix, rotationMatrix), scaleMatrix)
        }
    }
    
    var scale: SIMD3<Float> {
        get {
            let sx = columns.0
            let sy = columns.1
            let sz = columns.2
            return simd_make_float3(length(sx), length(sy), length(sz))
        }
        set {
            columns.0 = columns.0 * (newValue.x / length(columns.0))
            columns.1 = columns.1 * (newValue.y / length(columns.1))
            columns.2 = columns.2 * (newValue.z / length(columns.2))
        }
    }
    
    ///Note: This only works if this transform is relative to nil, otherwise it converts to the parent Entity's coordinate space.
    func convertPositionToWorldSpace(_ inputPosition: simd_float3) -> simd_float3 {
        // Convert the positions from local anchor-space coordinates to world coordinates.
        var centerLocalTransform = matrix_identity_float4x4
        centerLocalTransform.columns.3 = SIMD4<Float>(inputPosition.x,
                                                      inputPosition.y,
                                                      inputPosition.z, 1)
        let centerWorldPosition = (self * centerLocalTransform).translation
        return centerWorldPosition
    }
    
    ///Linearly interpolates between x and y, taking the value x when t=0 and y when t=1
    static func mix(x: float4x4, y: float4x4, t: Float) -> float4x4 {
        var newTransform = simd_float4x4(diagonal: [1,1,1,1])
        
        newTransform.orientation = simd_slerp(x.orientation, y.orientation, t)
        
        newTransform.translation = simd_mix(x.translation, y.translation, .init(repeating: t))

        newTransform.scale = simd_mix(x.scale, y.scale, .init(repeating: t))
        
        return newTransform
    }
}
extension float4x4: CustomStringConvertible {
    ///Calling print(myMatrix) prints the *columns* one after another, horizontally. This function allows us to visualize the actual matrix with the columns laid out vertically and the rows laid out horizontally.
    /// - Values are rounded to the nearest hundredths place to keep columns and rows aligned visually.
    public var description: String {
        var result = String()
        let columnsArray = [columns.0,
                       columns.1,
                       columns.2,
                       columns.3]
        for y in 0...3 {
            var rowString = String()
            for x in 0...3 {
                let value = columnsArray[x][y]
                //Round all numbers to hundredths to keep columns and rows aligned when printing out.
                rowString.append(contentsOf: String(format: "%.2f ", value))
            }
            result.append(rowString + "\n")
        }
        return result
    }
}
public extension float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3.x = translation.x
        columns.3.y = translation.y
        columns.3.z = translation.z
    }
    init(scale: SIMD3<Float>) {
        var localMatrix = matrix_identity_float4x4
        localMatrix.scale = scale
        self = localMatrix
    }

    init(rotationX angle: Float) {
        self = matrix_identity_float4x4
        columns.1.y = cos(angle)
        columns.1.z = sin(angle)
        columns.2.y = -sin(angle)
        columns.2.z = cos(angle)
    }

    init(rotationY angle: Float) {
        self = matrix_identity_float4x4
        columns.0.x = cos(angle)
        columns.0.z = -sin(angle)
        columns.2.x = sin(angle)
        columns.2.z = cos(angle)
    }

    init(rotationZ angle: Float) {
        self = matrix_identity_float4x4
        columns.0.x = cos(angle)
        columns.0.y = sin(angle)
        columns.1.x = -sin(angle)
        columns.1.y = cos(angle)
    }

    init(rotation angle: SIMD3<Float>) {
        let rotationX = float4x4(rotationX: angle.x)
        let rotationY = float4x4(rotationY: angle.y)
        let rotationZ = float4x4(rotationZ: angle.z)
        self = rotationX * rotationY * rotationZ
    }

    init(projectionFov fov: Float, near: Float, far: Float, aspect: Float, lhs: Bool = true) {
        let yValue = 1 / tan(fov * 0.5)
        let xValue = yValue / aspect
        let zValue = lhs ? far / (far - near) : far / (near - far)
        let x2Value = SIMD4<Float>(xValue, 0, 0, 0)
        let y2Value = SIMD4<Float>(0, yValue, 0, 0)
        let z2Value = lhs ? SIMD4<Float>(0, 0, zValue, 1) : SIMD4<Float>(0, 0, zValue, -1)
        let wValue = lhs ? SIMD4<Float>(0, 0, zValue * -near, 0) : SIMD4<Float>(0, 0, zValue * near, 0)
        self.init()
        columns = (x2Value, y2Value, z2Value, wValue)
    }

    /// Build a transform from the position and normal (up vector, perpendicular to surface)
    init(_ position: SIMD3<Float>, normal: SIMD3<Float>) {

        let absX = abs(normal.x)
        let absY = abs(normal.y)
        let abzZ = abs(normal.z)
        let yAxis = normalize(normal)
        // find a vector sufficiently different from yAxis
        var notYAxis = yAxis
        if absX <= absY, absX <= abzZ {
            // y of yAxis is smallest component
            notYAxis.x = 1
        } else if absY <= absX, absY <= abzZ {
            // y of yAxis is smallest component
            notYAxis.y = 1
        } else if abzZ <= absX, abzZ <= absY {
            // z of yAxis is smallest component
            notYAxis.z = 1
        } else {
            fatalError("couldn't find perpendicular axis")
        }
        let xAxis = normalize(cross(notYAxis, yAxis))
        let zAxis = cross(xAxis, yAxis)

        self = float4x4(SIMD4<Float>(xAxis, w: 0.0),
                        SIMD4<Float>(yAxis, w: 0.0),
                        SIMD4<Float>(zAxis, w: 0.0),
                        SIMD4<Float>(position, w: 1.0))
    }

    var upVector: SIMD3<Float> {
        return SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z)
    }

    var rightVector: SIMD3<Float> {
        return SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z)
    }

    var forwardVector: SIMD3<Float> {
        return SIMD3<Float>(-columns.2.x, -columns.2.y, -columns.2.z)
    }

    var position: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}

//MARK: - Transform extensions
public extension Transform {
    init(_ position: SIMD3<Float>, normal: SIMD3<Float>) {
        self.init(matrix: float4x4(position, normal: normal))
    }

    var upVector: SIMD3<Float> {
        return normalize(matrix.columns.1.xyz)
    }

    var rightVector: SIMD3<Float> {
        return normalize(matrix.columns.0.xyz)
    }

    var forwardVector: SIMD3<Float> {
        return normalize(-matrix.columns.2.xyz)
    }
}
