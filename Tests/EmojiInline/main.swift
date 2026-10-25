import Foundation
import CoreGraphics
@main struct Checks {
    static func token(_ text: String, caret: Int? = nil) -> EmojiInlinePolicy.Token? {
        EmojiInlinePolicy.match(text:text,selection:NSRange(location:caret ?? text.utf16.count,length:0))
    }
    static func main() {
        var gate = EmojiInlineInputGate()
        gate.foreground(42); gate.down(1,eligible:true); assert(gate.up(1,eligible:true) == nil)
        gate.configure(enabled:true)
        gate.down(1,eligible:true); gate.down(2,eligible:true); gate.down(3,eligible:true)
        assert(gate.up(2,eligible:true) == nil && gate.up(1,eligible:true) == nil)
        let rolled = gate.up(3,eligible:true)!
        assert(gate.isCurrent(rolled))
        gate.down(4,eligible:true); assert(!gate.isCurrent(rolled)); assert(gate.up(4,eligible:true) != nil)
        gate.down(1,eligible:true); gate.down(1,eligible:false); assert(gate.up(1,eligible:true) == nil)
        gate.down(1,eligible:true); gate.down(2,eligible:true,target:99); assert(gate.up(1,eligible:true) == nil)
        gate.down(1,eligible:true); assert(gate.up(99,eligible:true) == nil && gate.up(1,eligible:true) == nil)
        for key in 0..<17 { gate.down(Int64(key),eligible:true) }
        for key in 0..<17 { assert(gate.up(Int64(key),eligible:true) == nil) }
        gate.down(1,eligible:true); gate.foreground(43); assert(gate.up(1,eligible:true) == nil)
        gate.down(1,eligible:true); gate.invalidate(); assert(gate.up(1,eligible:true) == nil)
        gate.down(1,eligible:true); gate.configure(enabled:false); assert(gate.up(1,eligible:true) == nil)
        print("Passed overlapping-key release order, stale tickets, repeat/rejected/unknown input, bounded chord, focus/configuration and reset refusal.")
        assert(token(":smi")?.choices.map(\.id) == ["smile","smiley"])
        assert(token("Hi (:SMI")?.choices.first?.id == "smile")
        assert(token(":smile:")?.choices.map(\.id) == ["smile"])
        assert(token("💻 :rocket")?.range == NSRange(location:3,length:7))
        for text in [":", "hello:smi", "::smile", "https://smile", "/:smi", ":smile ", ":not_an_alias", ":s mí", String(repeating:"x",count:66)] { assert(token(text) == nil, text) }
        assert(token(":smile",caret:3) == nil)
        assert(EmojiInlinePolicy.match(text:":sm",selection:NSRange(location:0,length:3)) == nil)
        assert(token("💻 :sm",caret:1) == nil)
        let first = token(":sm")!
        var value = SnippetEditTransaction.Snapshot(text:":sm",selection:NSRange(location:3,length:0))
        let original = value
        var valid = true, writes = 0
        let success = SnippetEditTransaction.apply(original:original,match:.init(range:first.range,template:first.choices[0].emoji,suffix:""),replacement:first.choices[0].emoji,
            read:{value},stillCurrent:{valid},select:{value.selection=$0;return true},replace:{_ in writes += 1;return true})
        assert(success && writes == 1)
        value = original; valid = false
        assert(!SnippetEditTransaction.apply(original:original,match:.init(range:first.range,template:"😄",suffix:""),replacement:"😄",read:{value},stillCurrent:{valid},select:{_ in fatalError("Stale selection")},replace:{_ in fatalError("Stale write")}))
        let screen = CGRect(x:0,y:0,width:1440,height:860)
        let frame = EmojiInlinePolicy.panelFrame(caret:CGRect(x:1400,y:800,width:0,height:20),primaryTop:900,screens:[screen],height:220)!
        assert(screen.contains(frame) && frame.width == 320)
        assert(EmojiInlinePolicy.panelFrame(caret:CGRect(x:0,y:0,width:0,height:0),primaryTop:900,screens:[screen],height:220) == nil)
        assert(EmojiInlinePolicy.panelFrame(caret:CGRect(x:0,y:0,width:0,height:20),primaryTop:.nan,screens:[screen],height:220) == nil)
        assert(EmojiInlinePolicy.panelFrame(caret:CGRect(x:0,y:0,width:0,height:20),primaryTop:900,screens:[CGRect(x:0,y:0,width:200,height:200)],height:220) == nil)
        print("Passed bounded colon-prefix/catalog/UTF-16/caret/boundary/closing-colon and popup geometry checks, plus stale selected-text transaction refusal. No editor, keyboard or clipboard accessed.")
    }
}
