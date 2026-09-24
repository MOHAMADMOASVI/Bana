import SwiftUI

struct StatusBadge: View {
    let status: RunStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
                .overlay {
                    if status == .running {
                        Circle().stroke(status.color.opacity(0.35), lineWidth: 3)
                    }
                }
            Text(status.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(status == .stopped ? Color.secondary : status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.13), in: Capsule())
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
            .background(
                LinearGradient(colors: [type.tint.opacity(0.22), type.tint.opacity(0.10)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityLabel(type.displayName)
    }
}
