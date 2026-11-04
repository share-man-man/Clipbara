import os.log

extension Logger {
    /// Subsystem of every Clipbara log. The release bundle ID for all builds, so
    /// one Console filter shows the logs of ClipbaraDev and ClipbaraLocal too.
    nonisolated static let clipbaraSubsystem = "com.minsang.PasteClip"

    /// A logger in Clipbara's subsystem.
    /// - Parameter category: the part of the app that logs, such as "StoreManager"
    nonisolated init(clipbaraCategory category: String) {
        self.init(subsystem: Self.clipbaraSubsystem, category: category)
    }
}
