import SwiftUI

enum RunStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case failed(String)

    var label: String {
        switch self {
        case .stopped: tr("متوقف", "Stopped")
        case .starting: tr("در حال شروع", "Starting")
        case .running: tr("در حال اجرا", "Running")
        case .stopping: tr("در حال توقف", "Stopping")
        case .failed: tr("خطا", "Error")
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
