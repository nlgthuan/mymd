// mymd: SwiftMath is built with plain swiftc rather than SwiftPM, so provide the
// `Bundle.module` that SwiftPM would generate. The app ships mathFonts.bundle in
// Contents/Resources, which is where Bundle.main looks.
import Foundation

extension Bundle {
    static var module: Bundle { Bundle.main }
}
