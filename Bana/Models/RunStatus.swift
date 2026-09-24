import SwiftUI

enum RunStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case failed(String)

    var label: String {
        switch self {
        case .stopped: "متوقف"
        case .starting: "در حال شروع"
        case .running: "در حال اجرا"
        case .stopping: "در حال توقف"
        case .failed: "خطا"
        }
    }

    var color: Color {
        switch self {
        case .stopped: .secondary
        case .starting, .stopping: .orange
        case .running: .green
        case .failed: .red
        }
    }

    /// A process exists (or is winding down) — Start must be disabled.
    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping: true
        default: false
        }
    }
}
