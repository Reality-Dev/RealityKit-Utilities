/*
  Bounding-box-based screen visibility utilities for RealityKit.

  Usage examples:

  if arView.isOnScreen(entity: boxEntity, margins: CGSize(width: 16, height: 32)) {
      // The entity’s projected bounding box intersects the visible screen area
  }

  if let overlay = arView.onScreenRect(for: characterEntity, clampedToScreen: true) {
      hudView.frame = overlay    // position a UIKit overlay over the entity
  }

  let fraction = arView.visibilityFraction(of: carEntity) // ~0.0 ... ~1.0
*/

#if !os(visionOS)
import RealityKit
import ARKit
import simd
import UIKit

// MARK: - Design Notes
// -----------------------------------------------------------------------------
// RealityKit culls by comparing each entity’s *bounding box* (plus any
// ModelComponent.boundsMargin) against the camera frustum. For UI overlays,
// hit-testing, or view-relative logic, testing a single world point is fragile.
// This utility computes a screen-space rectangle from the WORLD-SPACE AABB by
// projecting its 8 corners through ARView.project(_:). The resulting rect
// matches what users actually see (under perspective).
//
// Why project all 8 corners?
// Under perspective, the screen-space extrema can come from any corner depending
// on camera pose/FOV; center/extents alone are insufficient. Projecting all 8 is
// the minimal, correct approach.
//
// Performance
// - Each call projects up to 8 points; this is cheap for per-frame use on a
//   handful of entities, but consider throttling if iterating over hundreds.
//
// Coordinate Spaces
// - visualBounds(recursive:relativeTo:nil) returns WORLD-SPACE bounds.
// - ARView.project(_:) expects WORLD-SPACE positions.
// - The on-screen rect is reported in ARView pixel coordinates (origin at top-left).
//
// Bounds Inflation
// - We automatically inflate bounds by ModelComponent.boundsMargin when present.
//   This mirrors RealityKit’s culling behavior and reduces “false negatives”
//   for meshes deformed/moved by geometry modifiers.
//

// MARK: - BoundingBox corner enumeration
// -----------------------------------------------------------------------------
/// Convenience access to the 8 axis-aligned corners of a `BoundingBox`.
/// The box is assumed to be axis-aligned in *world space* at the time you call it.
private extension BoundingBox {
    /// The 8 corners of the AABB, derived from `min`/`max`.
    var corners: [SIMD3<Float>] {
        let a = min, b = max
        return [
            SIMD3(a.x, a.y, a.z), SIMD3(b.x, a.y, a.z),
            SIMD3(a.x, b.y, a.z), SIMD3(b.x, b.y, a.z),
            SIMD3(a.x, a.y, b.z), SIMD3(b.x, a.y, b.z),
            SIMD3(a.x, b.y, b.z), SIMD3(b.x, b.y, b.z)
        ]
    }
}

// MARK: - Entity ➜ screen rect
// -----------------------------------------------------------------------------
public extension Entity {
    /// Computes a 2D rectangle in the ARView’s screen space that tightly encloses
    /// the projection of this entity’s world-space axis-aligned bounding box.
    ///
    /// - Parameters:
    ///   - view: The `ARView` used for projection.
    ///   - recursive: If `true`, includes descendants when computing `visualBounds`.
    ///   - excludeInactive: Exclude inactive entities from the bounds computation.
    /// - Returns: A `CGRect` in the ARView’s pixel coordinate system, or `nil` if
    ///   none of the corners project (e.g., fully behind the camera or no valid projection).
    ///
    /// - Note: Utilize `ModelComponent.boundsMargin` to expand the visible bounds based on any vertex shader effects. This method will take that value into account.
    func screenBoundingRect(
        in view: ARView,
        recursive: Bool = true,
        excludeInactive: Bool = false
    ) -> CGRect? {

        // WORLD-SPACE bounds for this entity (and children, if requested).
        var box = visualBounds(
            recursive: recursive,
            relativeTo: nil,
            excludeInactive: excludeInactive
        )

        // Inflate by this entity’s ModelComponent.boundsMargin (if present).
        if let model = components[ModelComponent.self] {
            // RealityKit adds boundsMargin to authored bounds for culling. Mirror that here.
            // TODO: RealityKit's documentation is unclear if this should be divided in half or added in full. i.e. "RealityKit adds the value of boundsMargin to the bounding box before determining which entities are visible."
            let m = SIMD3<Float>(repeating: model.boundsMargin)
            box.min -= m
            box.max += m
        }

        // Project each corner from world space to screen space.
        let projectedPoints: [CGPoint] = box.corners.compactMap { worldCorner in
            guard let p = view.project(worldCorner) else { return nil } // filtered if behind camera
            return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        }

        // If nothing projects, treat as not visible on screen.
        guard let first = projectedPoints.first else { return nil }

        // Union all points to build a tight 2D rect.
        var rect = CGRect(origin: first, size: .zero)
        for pt in projectedPoints.dropFirst() {
            rect = rect.union(CGRect(origin: pt, size: .zero))
        }
        return rect
    }
}

// MARK: - ARView conveniences
// -----------------------------------------------------------------------------
@MainActor
public extension ARView {
    /// Tests whether an entity’s *projected bounding box* intersects the current
    /// on-screen area of this ARView.
    ///
    /// This check is superior to a single-point test because it reflects the
    /// geometry’s actual on-screen footprint under perspective.
    ///
    /// - Parameters:
    ///   - entity: The entity to test.
    ///   - margins: Insets applied to the screen rectangle before intersection.
    ///              Positive values shrink the usable screen area, making the test stricter.
    ///   - recursive: If `true`, includes descendants in the bounds computation.
    ///   - excludeInactive: Exclude inactive entities when computing bounds.
    /// - Returns: `true` if the projected bounding box intersects the (inset) screen.
    func isOnScreen(
        entity: Entity,
        margins: CGSize = .zero,
        recursive: Bool = true,
        excludeInactive: Bool = false
    ) -> Bool {
        guard let rect = entity.screenBoundingRect(
            in: self,
            recursive: recursive,
            excludeInactive: excludeInactive
        ) else {
            return false
        }

        let screenRect = CGRect(origin: .zero, size: frame.size)
            .insetBy(dx: margins.width, dy: margins.height)

        return rect.intersects(screenRect)
    }

    /// Computes the entity’s on-screen rectangle, optionally *clamped* to the view’s
    /// bounds — useful for placing HUD elements that shouldn’t spill off-screen.
    ///
    /// - Parameters:
    ///   - entity: The entity of interest.
    ///   - clampedToScreen: If `true`, the returned rectangle is intersected with the
    ///     ARView’s bounds; if the entity is fully off-screen, returns `nil`.
    ///   - recursive: If `true`, includes descendants in the bounds computation.
    ///   - excludeInactive: Exclude inactive entities when computing bounds.
    /// - Returns: The (possibly clamped) on-screen rect in pixel coordinates, or `nil`.
    func onScreenRect(
        for entity: Entity,
        clampedToScreen: Bool = false,
        recursive: Bool = true,
        excludeInactive: Bool = false
    ) -> CGRect? {
        guard var rect = entity.screenBoundingRect(
            in: self,
            recursive: recursive,
            excludeInactive: excludeInactive
        ) else {
            return nil
        }

        if clampedToScreen {
            let screenRect = CGRect(origin: .zero, size: frame.size)
            rect = rect.intersection(screenRect)
            if rect.isNull || rect.isEmpty { return nil }
        }
        return rect
    }

    /// Estimates how much of the entity’s projected bounding box is visible on screen.
    ///
    /// This is a **conservative approximation** that computes the ratio:
    ///
    ///     area( onScreenRect(entity) ∩ screen ) / area( onScreenRect(entity) )
    ///
    /// Because it uses the *bounding box* projection (not the true silhouette),
    /// values may overestimate visibility for sparse meshes. Still, it’s handy for
    /// thresholding UI behavior (e.g., fade in labels when ≥ 20% visible).
    ///
    /// - Parameters:
    ///   - entity: The entity to measure.
    ///   - recursive: If `true`, includes descendants in the bounds computation.
    ///   - excludeInactive: Exclude inactive entities when computing bounds.
    /// - Returns: A value in `[0, 1]` (best effort), or `0` if fully off-screen.
    func visibilityFraction(
        of entity: Entity,
        recursive: Bool = true,
        excludeInactive: Bool = false
    ) -> CGFloat {
        guard let rect = entity.screenBoundingRect(
            in: self,
            recursive: recursive,
            excludeInactive: excludeInactive
        ) else {
            return 0
        }

        let screenRect = CGRect(origin: .zero, size: frame.size)
        let clipped = rect.intersection(screenRect)

        let rectArea = rect.width * rect.height
        guard rectArea > 0 else { return 0 }

        let clippedArea = max(0, clipped.width) * max(0, clipped.height)
        return CGFloat(min(max(clippedArea / rectArea, 0), 1))
    }

    // MARK: - Legacy convenience: single-world-point test
    // -------------------------------------------------------------------------
    /// Tests whether a single world-space point projects into
    /// the (optionally inset) screen bounds.
    ///
    /// Suitable for Entities without a `ModelComponent`, gizmos, etc.
    func isPointOnScreen(
        worldPosition: SIMD3<Float>,
        margins: CGSize = .zero
    ) -> Bool {
        guard let sp = project(worldPosition) else { return false }
        let w = (0 + margins.width)  ... (frame.size.width  - margins.width)
        let h = (0 + margins.height) ... (frame.size.height - margins.height)
        return w.contains(sp.x) && h.contains(sp.y)
    }

    /// Tests whether a single world-space point (the anchor's origin) projects into
    /// the (optionally inset) screen bounds.
    func isOriginOnScreen(
        anchor: ARAnchor,
        margins: CGSize = .zero
    ) -> Bool {
        isPointOnScreen(worldPosition: anchor.transform.translation, margins: margins)
    }
}
#endif
