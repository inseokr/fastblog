import Foundation

/// Persists the chosen **bundled** slideshow track per recap blog (`UserDefaults`, keyed by blog UUID).
enum SlideshowMusicPreference {
    private static let defaults = UserDefaults.standard

    /// Sentinel stored when the user explicitly picks "No background music",
    /// so we can distinguish that from "never chosen" (which uses the default track).
    static let explicitNoneSentinel = "__none__"

    /// Default track filename used when no preference has ever been saved for a blog.
    static let defaultFilename = "burtysounds-happy-124917.mp3"

    private static func filenameKey(blogId: String) -> String {
        "slideshow.bundled.filename.\(blogId)"
    }

    private static func titleKey(blogId: String) -> String {
        "slideshow.bundled.title.\(blogId)"
    }

    struct Saved: Equatable {
        var filename: String
        var displayTitle: String?
        /// True when the user explicitly chose "No background music".
        var isExplicitNone: Bool { filename == explicitNoneSentinel }
    }

    static func load(blogId: String) -> Saved? {
        guard let fn = defaults.string(forKey: filenameKey(blogId: blogId)), !fn.isEmpty else { return nil }
        return Saved(filename: fn, displayTitle: defaults.string(forKey: titleKey(blogId: blogId)))
    }

    static func save(blogId: String, filename: String, displayTitle: String?) {
        defaults.set(filename, forKey: filenameKey(blogId: blogId))
        if let title = displayTitle, !title.isEmpty {
            defaults.set(title, forKey: titleKey(blogId: blogId))
        } else {
            defaults.removeObject(forKey: titleKey(blogId: blogId))
        }
    }

    /// Call when the user explicitly picks "No background music" so the default is not re-applied on next open.
    static func saveNone(blogId: String) {
        defaults.set(explicitNoneSentinel, forKey: filenameKey(blogId: blogId))
        defaults.removeObject(forKey: titleKey(blogId: blogId))
    }

    static func clear(blogId: String) {
        defaults.removeObject(forKey: filenameKey(blogId: blogId))
        defaults.removeObject(forKey: titleKey(blogId: blogId))
    }

    /// Resolves a file included in the app bundle (e.g. `slideshow_theme.m4a`).
    static func bundleURL(forBundledFilename filename: String) -> URL? {
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        return Bundle.main.url(forResource: base, withExtension: ext)
    }
}
