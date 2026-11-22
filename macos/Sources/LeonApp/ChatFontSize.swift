import SwiftUI

struct ChatFontSize: Equatable {
    static let defaultPoints = 14
    static let pointRange = 12...24

    let points: Int

    init(_ points: Int = Self.defaultPoints) {
        self.points = min(max(points, Self.pointRange.lowerBound), Self.pointRange.upperBound)
    }

    var scale: CGFloat { CGFloat(points) / CGFloat(Self.defaultPoints) }

    func scaled(_ baseSize: CGFloat) -> CGFloat { baseSize * scale }
}

private struct ChatFontSizeKey: EnvironmentKey {
    static let defaultValue = ChatFontSize()
}

extension EnvironmentValues {
    var chatFontSize: ChatFontSize {
        get { self[ChatFontSizeKey.self] }
        set { self[ChatFontSizeKey.self] = newValue }
    }
}
