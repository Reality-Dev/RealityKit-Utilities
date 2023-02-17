/*
See the LICENSE file and the LICENSE ORIGINS folder for this sample’s licensing information.
 */

import CoreGraphics
import simd
import SceneKit

// MARK: - CGPoint extensions
public extension CGPoint {

    /// Extracts the screen space point from a vector returned by SCNView.projectPoint(_:).
    init(_ vector: SCNVector3) {
        self.init(x: CGFloat(vector.x), y: CGFloat(vector.y))
    }
    
    func simdVect() -> simd_float2 {
        return simd_float2(Float(self.x), Float(self.y))
    }
    
    func distance(from point: CGPoint) -> CGFloat {
        return hypot(point.x - x, point.y - y)
    }
    
    static func midPoint(p1: CGPoint, p2: CGPoint) -> CGPoint {
        return CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }

    /// Returns the length of a point when considered as a vector. (Used with gesture recognizers.)
    var length: CGFloat {
        return sqrt(x * x + y * y)
    }
    
    static func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint{
        return CGPoint(x: lhs.x + rhs.x,
                       y: lhs.y + rhs.y)
    }
    
    static func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint{
        return CGPoint(x: lhs.x - rhs.x,
                       y: lhs.y - rhs.y)
    }
    
    static func +(lhs: CGPoint, rhs: CGSize) -> CGPoint{
        return CGPoint(x: lhs.x + rhs.width,
                       y: lhs.y + rhs.height)
    }
}

// MARK: - CGSize extensions
public extension CGSize {
    func lerp(newValue: CGSize, amount: CGFloat)-> CGSize {
        let amount = amount.clamped(0.0, 1.0)
        return self + ((newValue - self) * amount)
    }
    
    static func +(lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width + rhs.width,
                      height: lhs.height + rhs.height)
    }
    
    static func -(lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width - rhs.width,
                      height: lhs.height - rhs.height)
    }

    static func *(lhs: CGSize, rhs: CGFloat) -> CGSize {
        return CGSize(width: lhs.width * rhs,
                      height: lhs.height * rhs)
    }
    
    func distance(to otherPoint: CGSize) -> Float {
        let xDifference = otherPoint.width - self.width
        let xSquared = xDifference * xDifference
        
        let yDifference = otherPoint.height - self.height
        let ySquared = yDifference * yDifference
        
        let sum = xSquared + ySquared
        
        return sqrtf(Float(sum))
    }
}

// MARK: - CGVector extensions
public extension CGVector {
    /// Returns the length of the vector. (Used with gesture recognizers.)
    var length: CGFloat {
        return sqrt(dx * dx + dy * dy)
    }
    
    /**
     * Adds two CGVector values and returns the result as a new CGVector.
     */
    static func +(lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(dx: lhs.dx + rhs.dx,
                        dy: lhs.dy + rhs.dy)
    }
    
    static func -(lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(dx: lhs.dx - rhs.dx,
                        dy: lhs.dy - rhs.dy)
    }
}
