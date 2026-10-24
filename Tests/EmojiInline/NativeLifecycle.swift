import AppKit
import Combine
import SwiftUI
struct Settings { var emojiInlineSuggestionsEnabled=false; var emojiDisabledAppBundleIDs:Set<String>=[] }
@MainActor final class SettingsModel { static let shared=SettingsModel(); @Published var settings=Settings(); var current:Settings {settings} }
@MainActor final class AppLockManager { static let shared=AppLockManager(); var isLocked=false }
enum EventTapDecision { case pass, swallow }
enum EventTapPriority { static let observer=100 }
final class GlobalEventTap {
    struct Token {}
    static let shared=GlobalEventTap()
    var registrations=0
    var body:((CGEventType,CGEvent)->EventTapDecision)?
    func register(name:String,mask:CGEventMask,priority:Int,reset:@escaping()->Void,_ body:@escaping(CGEventType,CGEvent)->EventTapDecision)->Token {registrations += 1;self.body=body;return Token()}
    func unregister(_ token:Token) {body=nil}
}
@main struct Native {
    @MainActor static func main() {
        _ = NSApplication.shared
        let manager=EmojiInlineSuggestionsManager.shared
        manager.start();manager.start();assert(GlobalEventTap.shared.registrations==0)
        SettingsModel.shared.settings.emojiInlineSuggestionsEnabled=true
        assert(GlobalEventTap.shared.registrations==1)
        SettingsModel.shared.settings.emojiInlineSuggestionsEnabled=false
        assert(GlobalEventTap.shared.body==nil)
        manager.stop();manager.start();assert(GlobalEventTap.shared.registrations==1);manager.stop()
        let view=NSHostingView(rootView:EmojiInlineChoicesView(choices:Array(EmojiInlinePolicy.catalog.prefix(5)),choose:{_ in fatalError("Unexpected click")} ).preferredColorScheme(.dark))
        view.frame=CGRect(x:0,y:0,width:320,height:230)
        let window=NSWindow(contentRect:CGRect(x:-10000,y:-10000,width:320,height:230),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=view;view.layoutSubtreeIfNeeded()
        if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/emoji-inline-tests/panel.png"))
        } else { fatalError("Offscreen render unavailable") }
        window.close()
        print("Passed real inline manager/panel/AX adapter compilation and opt-in/disable/teardown with fake settings and inert hooks; synthetic popup rendered offscreen. No actual event tap, user text, clipboard or app activation.")
    }
}
