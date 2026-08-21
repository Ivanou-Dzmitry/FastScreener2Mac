import Foundation

// SwiftPM's auto-generated Bundle.module only checks two locations: right
// beside the executable (works for `swift run`/`swift build`), or directly
// inside a packaged .app's own root folder — which codesign rejects as
// "unsealed contents present in the bundle root" once the app is signed
// and distributed, since only Contents/ is covered by the seal. This adds
// Contents/Resources (where the release .app actually ships the bundle)
// as a candidate before falling back to Bundle.module.
enum AppResourceBundle {
    private static let bundleName = "FastScreenerMac_FastScreenerMac.bundle"

    static let shared: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(path: resourceURL.appendingPathComponent(bundleName).path) {
            return bundle
        }
        return Bundle.module
    }()
}
