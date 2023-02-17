/*
See LICENSE folder for this sample’s licensing information.
 */

import CoreGraphics
import simd
import SceneKit

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
    
    static func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint{
        return CGPoint(x: lhs.x - rhs.x,
                       y: lhs.y - rhs.y)
    }
    
    static func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint{
        return CGPoint(x: lhs.x + rhs.x,
                       y: lhs.y + rhs.y)
    }
    
    static func *(lhs: CGPoint, rhs: CGFloat) -> CGPoint{
        return CGPoint(x: lhs.x * rhs,
                       y: lhs.y * rhs)
    }
    
    static func /(lhs: CGPoint, rhs: CGFloat) -> CGPoint{
        return CGPoint(x: lhs.x / rhs,
                       y: lhs.y / rhs)
    }
}
