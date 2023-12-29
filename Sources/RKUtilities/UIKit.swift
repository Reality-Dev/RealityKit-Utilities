/*
See the LICENSE file and the LICENSE ORIGINS folder for this sample’s licensing information.
 */

#if canImport(UIKit)
import UIKit

// MARK: - UIScreen extensions
public extension UIScreen{
    static let screenWidth = UIScreen.main.bounds.size.width
    static let screenHeight = UIScreen.main.bounds.size.height
    static let screenSize = UIScreen.main.bounds.size
}

// MARK: - UIView extensions
public extension UIView {
    
    func setSuperView(_ newParent: UIView){
        newParent.addSubview(self)
    }
    
    func roundCorners(amount: CGFloat = 8){
        self.layer.cornerRadius = amount
        self.clipsToBounds = true
    }
    
    func removeWithFade(duration: TimeInterval = 1.0){
        fadeOut(duration: duration){
            self.isHidden = true
            self.removeFromSuperview()
        }
    }
    
    /**
    Fade in a view with a duration
    - parameter duration: custom animation duration
    */
    func fadeIn(duration: TimeInterval = 1.0, completion: (() -> Void)? = nil) {
        self.isHidden = false
     UIView.animate(withDuration: duration, animations: {
         self.alpha = 1.0
     },  completion: { finished in
         if finished {
             completion?()
             }
         })
     }
    
    /**
   Fade out a view with a duration
   - parameter duration: custom animation duration
   */
    func fadeOut(duration: TimeInterval = 1.0, completion: (() -> Void)? = nil) {
     UIView.animate(withDuration: duration, animations: {
         self.alpha = 0.0
     },  completion: { finished in
         if finished {
             // Could be a good place to set `isHidden` to true
             completion?()
             }
         })
     }
}
#endif
