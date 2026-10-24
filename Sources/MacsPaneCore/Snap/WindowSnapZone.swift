import CoreGraphics

/// A target region a window can snap to, expressed against a screen's *visible* frame (AppKit
/// bottom-left origin, matching `NSScreen.visibleFrame`) so a snapped window clears the menu bar
/// and Dock. Pure geometry, no AppKit, so it lives in Core and is unit-testable, the same
/// discipline as `NotchGeometry`.
///
/// The case declaration order is also the catalog's display order, `allCases` drives both the
/// default region list and the Settings picker, so the cases are grouped maximize → halves →
/// quarters → vertical thirds/two-thirds → horizontal thirds/two-thirds. (Raw values are the case
/// names, so reordering is safe for persistence.)
public enum WindowSnapZone: String, CaseIterable, Codable, Sendable, Identifiable {
    case maximize
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case topThird, middleThird, bottomThird
    case topTwoThirds, bottomTwoThirds

    public var id: String { rawValue }

    /// The target frame within a screen's visible area, in AppKit bottom-left coordinates. Note the
    /// Y convention: in bottom-left space the *top* half/quarters have the higher Y (`midY`), the
    /// *bottom* ones sit at `minY`. The whole point of working from `visibleFrame` is that the menu
    /// bar and Dock are already excluded, so each zone is just a fraction of that rect.
    public func frame(in v: CGRect) -> CGRect {
        let halfW = v.width / 2
        let halfH = v.height / 2
        let thirdW = v.width / 3
        let thirdH = v.height / 3
        switch self {
        case .maximize:           return v
        case .leftHalf:           return CGRect(x: v.minX,           y: v.minY,           width: halfW,       height: v.height)
        case .rightHalf:          return CGRect(x: v.midX,           y: v.minY,           width: halfW,       height: v.height)
        case .topHalf:            return CGRect(x: v.minX,           y: v.midY,           width: v.width,     height: halfH)
        case .bottomHalf:         return CGRect(x: v.minX,           y: v.minY,           width: v.width,     height: halfH)
        case .topLeftQuarter:     return CGRect(x: v.minX,           y: v.midY,           width: halfW,       height: halfH)
        case .topRightQuarter:    return CGRect(x: v.midX,           y: v.midY,           width: halfW,       height: halfH)
        case .bottomLeftQuarter:  return CGRect(x: v.minX,           y: v.minY,           width: halfW,       height: halfH)
        case .bottomRightQuarter: return CGRect(x: v.midX,           y: v.minY,           width: halfW,       height: halfH)
        case .leftThird:          return CGRect(x: v.minX,           y: v.minY,           width: thirdW,      height: v.height)
        case .centerThird:        return CGRect(x: v.minX + thirdW,  y: v.minY,           width: thirdW,      height: v.height)
        case .rightThird:         return CGRect(x: v.maxX - thirdW,  y: v.minY,           width: thirdW,      height: v.height)
        case .leftTwoThirds:      return CGRect(x: v.minX,           y: v.minY,           width: thirdW * 2,  height: v.height)
        case .rightTwoThirds:     return CGRect(x: v.minX + thirdW,  y: v.minY,           width: thirdW * 2,  height: v.height)
        case .topThird:           return CGRect(x: v.minX,           y: v.maxY - thirdH,  width: v.width,     height: thirdH)
        case .middleThird:        return CGRect(x: v.minX,           y: v.minY + thirdH,  width: v.width,     height: thirdH)
        case .bottomThird:        return CGRect(x: v.minX,           y: v.minY,           width: v.width,     height: thirdH)
        case .topTwoThirds:       return CGRect(x: v.minX,           y: v.minY + thirdH,  width: v.width,     height: thirdH * 2)
        case .bottomTwoThirds:    return CGRect(x: v.minX,           y: v.minY,           width: v.width,     height: thirdH * 2)
        }
    }

    /// Human-readable name (menus, tooltips, the optional `snapprobe` CLI).
    public var displayName: String {
        switch self {
        case .maximize:           return "Maximize"
        case .leftHalf:           return "Left Half"
        case .rightHalf:          return "Right Half"
        case .topHalf:            return "Top Half"
        case .bottomHalf:         return "Bottom Half"
        case .topLeftQuarter:     return "Top-Left Quarter"
        case .topRightQuarter:    return "Top-Right Quarter"
        case .bottomLeftQuarter:  return "Bottom-Left Quarter"
        case .bottomRightQuarter: return "Bottom-Right Quarter"
        case .leftThird:          return "Left Third"
        case .centerThird:        return "Center Third"
        case .rightThird:         return "Right Third"
        case .leftTwoThirds:      return "Left Two-Thirds"
        case .rightTwoThirds:     return "Right Two-Thirds"
        case .topThird:           return "Top Third"
        case .middleThird:        return "Middle Third"
        case .bottomThird:        return "Bottom Third"
        case .topTwoThirds:       return "Top Two-Thirds"
        case .bottomTwoThirds:    return "Bottom Two-Thirds"
        }
    }
}
