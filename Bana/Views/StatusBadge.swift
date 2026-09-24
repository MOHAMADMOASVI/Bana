import SwiftUI

struct StatusBadge: View {
    let status: RunStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text(status.label)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(status == .stopped ? Color.secondary : status.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.14), in: Capsule())
        .help(helpText)
    }

    private var helpText: String {
        if case .failed(let message) = status { return message.rtl }
        return status.label
    }
}

struct TypeIcon: View {
    let type: ProjectType
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: type.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(type.tint)
            .frame(width: size, height: size)
            .background(type.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityLabel(type.displayName)
    }
}
