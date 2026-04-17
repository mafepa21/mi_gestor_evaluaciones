import SwiftUI

struct AppRectCorner: OptionSet {
    let rawValue: Int

    static let topLeft = AppRectCorner(rawValue: 1 << 0)
    static let topRight = AppRectCorner(rawValue: 1 << 1)
    static let bottomLeft = AppRectCorner(rawValue: 1 << 2)
    static let bottomRight = AppRectCorner(rawValue: 1 << 3)
    static let allCorners: AppRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

extension View {
    func appCornerRadius(_ radius: CGFloat, corners: AppRectCorner) -> some View {
        clipShape(AppRoundedCorner(radius: radius, corners: corners))
    }
}

struct AppRoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: AppRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let topLeft = corners.contains(.topLeft) ? radius : 0
        let topRight = corners.contains(.topRight) ? radius : 0
        let bottomRight = corners.contains(.bottomRight) ? radius : 0
        let bottomLeft = corners.contains(.bottomLeft) ? radius : 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
            radius: topRight,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
            radius: bottomRight,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
            radius: bottomLeft,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(
            center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
            radius: topLeft,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
