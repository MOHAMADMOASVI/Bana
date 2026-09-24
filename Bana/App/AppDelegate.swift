import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppAppearance.current.apply() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Never leave orphaned servers behind: stop every process tree, then quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = MainActor.assumeIsolated { ProjectStore.shared }
        let running = MainActor.assumeIsolated { store.runningCount }
        guard running > 0 else { return .terminateNow }
        MainActor.assumeIsolated {
            store.stopAll { sender.reply(toApplicationShouldTerminate: true) }
        }
        // Safety net if a process ignores even SIGKILL bookkeeping.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
