import SwiftUI

struct MaterialColor {
    static let folderDarkBlue = Color(red: 0.1, green: 0.2, blue: 0.35)
    static let folderLightBorder = Color(red: 0.3, green: 0.4, blue: 0.55)
    static let folderHandle = Color(red: 0.05, green: 0.1, blue: 0.2)
}

struct FolderTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Tab parameters relative to rect
        let tabWidth: CGFloat = rect.width * 0.4 // 40% tab width
        let tabHeight: CGFloat = rect.height
        let cornerRadius: CGFloat = 8
        
        // Start top-left (rounded)
        path.move(to: CGPoint(x: 0, y: cornerRadius))
        path.addArc(center: CGPoint(x: cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        
        // Top edge of tab
        path.addLine(to: CGPoint(x: tabWidth - cornerRadius, y: 0))
        
        // Slope down (Tab ending)
        // Let's do a smooth slope or S-curve? Standard folder is usually lines.
        path.addLine(to: CGPoint(x: tabWidth + 10, y: tabHeight))
        
        // Bottom right (end of tab logic, connect to rect?)
        // Actually this shape is JUST the tab or the whole folder?
        // Let's make this shape the TOP TAB only.
        path.addLine(to: CGPoint(x: 0, y: tabHeight))
        path.closeSubpath()
        
        return path
    }
}
