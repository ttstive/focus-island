import Foundation

public struct TrackedEditor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) {
        self.id = id.lowercased()
        self.name = name
    }
}

public enum EditorCatalog {
    /// Match application identities exactly, never a vendor-wide prefix that might
    /// include an updater, launcher, browser, or background helper process.
    public static let builtIns: [TrackedEditor] = [
        .init(id: "com.microsoft.VSCode", name: "VS Code"),
        .init(id: "com.microsoft.VSCodeInsiders", name: "VS Code Insiders"),
        .init(id: "com.apple.dt.Xcode", name: "Xcode"),
        .init(id: "com.jetbrains.datagrip", name: "DataGrip"),
        .init(id: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        .init(id: "com.jetbrains.intellij.ce", name: "IntelliJ IDEA Community"),
        .init(id: "com.jetbrains.pycharm", name: "PyCharm"),
        .init(id: "com.jetbrains.pycharm.ce", name: "PyCharm Community"),
        .init(id: "com.jetbrains.WebStorm", name: "WebStorm"),
        .init(id: "com.jetbrains.PhpStorm", name: "PhpStorm"),
        .init(id: "com.jetbrains.CLion", name: "CLion"),
        .init(id: "com.jetbrains.goland", name: "GoLand"),
        .init(id: "com.jetbrains.rider", name: "Rider"),
        .init(id: "com.jetbrains.rubymine", name: "RubyMine"),
        .init(id: "com.google.android.studio", name: "Android Studio"),
        .init(id: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        .init(id: "com.exafunction.windsurf", name: "Windsurf"),
        .init(id: "dev.zed.Zed", name: "Zed"),
        .init(id: "com.sublimetext.4", name: "Sublime Text")
    ]
    public static let defaultIDs = Set(builtIns.map(\.id))
    public static func contains(_ bundleID: String?, in enabledIDs: Set<String>) -> Bool {
        guard let bundleID else { return false }
        return enabledIDs.contains(bundleID.lowercased())
    }
    public static func merging(_ custom: [TrackedEditor]) -> [TrackedEditor] {
        var seen = defaultIDs
        return builtIns + custom.compactMap { editor in
            let normalized = TrackedEditor(id: editor.id, name: editor.name)
            guard !normalized.id.isEmpty, seen.insert(normalized.id).inserted else { return nil }
            return normalized
        }
    }
}
