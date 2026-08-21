import Foundation
import ObjectiveC.runtime
import iosMath

/// SwiftPM's generated Objective-C resource accessor looks beside a command-line
/// executable, but a signed macOS app must keep resources inside Contents/Resources.
/// Redirect iosMath's private bundle lookup before the first formula is rendered.
enum IOSMathResourceLocator {
    static func install() {
        guard let resourcesURL = Bundle.main.resourceURL,
              let bundle = Bundle(
                url: resourcesURL.appendingPathComponent("iosMath_iosMath.bundle", isDirectory: true)
              ),
              let method = class_getClassMethod(MTFont.self, NSSelectorFromString("fontBundle")) else {
            return
        }
        let block: @convention(block) (AnyObject) -> Bundle = { _ in bundle }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
