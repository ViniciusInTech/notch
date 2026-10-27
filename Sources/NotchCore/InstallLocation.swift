import Foundation

public enum InstallLocation {
    /// Only places a downloaded copy usually lands in; development builds elsewhere are left alone.
    public static func shouldOfferMove(bundlePath: String, homeDirectory: String) -> Bool {
        let path = (bundlePath as NSString).standardizingPath
        let home = (homeDirectory as NSString).standardizingPath
        if path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") { return false }
        return path.hasPrefix("/Volumes/") || path.hasPrefix(home + "/Downloads/")
            || path.contains("/AppTranslocation/")
    }

    /// The mounted disk image holding the app, so it can be ejected after moving.
    public static func mountedVolume(bundlePath: String) -> String? {
        let parts = (bundlePath as NSString).standardizingPath.split(separator: "/")
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        return "/Volumes/" + parts[1]
    }
}
