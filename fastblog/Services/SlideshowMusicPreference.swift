import Foundation

/// Persists the chosen **bundled** slideshow track per recap blog (`UserDefaults`, keyed by blog UUID).
enum SlideshowMusicPreference {
    private static let defaults = UserDefaults.standard

    private static func filenameKey(blogId: String) -> String {
        "slideshow.bundled.filename.\(blogId)"
    }

    private static func titleKey(blogId: String) -> String {
        "slideshow.bundled.title.\(blogId)"
    }

    struct Saved: Equatable {
        var filename: String
        var displayTitle: String?
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
