import Foundation
import CoreGraphics
@main struct KeySelectionTests {
    static func main() {
        let keys = (0..<5).map { KeyGeometry(id:"K\($0)",label:"\($0)",x:Double($0),y:0,width:1,height:1) } +
            [KeyGeometry(id:"Tall",label:"+",x:5,y:0,width:1,height:2),KeyGeometry(id:"Space",label:"Space",x:0,y:2,width:5,height:1)]
        var smartBox=KeySelectionDrag(tool:.automatic,start:CGPoint(x:-0.3,y:-0.3),initial:[],keys:keys)
        assert(smartBox.update(to:CGPoint(x:3,y:1),keys:keys) == ["K0","K1","K2"])
        assert(smartBox.tool == .rectangle && smartBox.rectangle != nil)
        var smartPaint=KeySelectionDrag(tool:.automatic,start:CGPoint(x:0.5,y:0.5),initial:[],keys:keys)
        assert(smartPaint.update(to:CGPoint(x:4.5,y:0.5),keys:keys).count == 5)
        assert(smartPaint.tool == .brush && smartPaint.rectangle == nil)
        var brush = KeySelectionDrag(tool:.brush,start:CGPoint(x:0.5,y:0.5),initial:[],keys:keys)
        assert(brush.update(to:CGPoint(x:4.5,y:0.5),keys:keys) == Set((0..<5).map { "K\($0)" }))
        assert(brush.update(to:CGPoint(x:0.5,y:0.5),keys:keys).count == 5)
        var erase = KeySelectionDrag(tool:.brush,start:CGPoint(x:0.5,y:0.5),initial:Set(keys.map(\.id)),keys:keys)
        assert(erase.update(to:CGPoint(x:3.5,y:0.5),keys:keys) == ["K4","Tall","Space"])
        assert(erase.update(to:CGPoint(x:0.5,y:0.5),keys:keys) == ["K4","Tall","Space"])
        var box = KeySelectionDrag(tool:.rectangle,start:CGPoint(x:0,y:0),initial:["Space"],keys:keys)
        assert(box.update(to:CGPoint(x:3,y:1),keys:keys) == ["K0","K1","K2"])
        assert(box.update(to:CGPoint(x:1,y:1),keys:keys) == ["K0"])
        var reverse = KeySelectionDrag(tool:.rectangle,start:CGPoint(x:6,y:2),initial:[],keys:keys)
        assert(reverse.update(to:CGPoint(x:5,y:1.5),keys:keys) == ["Tall"])
        var add = KeySelectionDrag(tool:.rectangle,start:CGPoint(x:0,y:0),initial:["Space"],keys:keys,adding:true)
        assert(add.update(to:CGPoint(x:2,y:1),keys:keys) == ["K0","K1","Space"])
        var remove = KeySelectionDrag(tool:.rectangle,start:CGPoint(x:0,y:0),initial:Set(keys.map(\.id)),keys:keys,removing:true)
        assert(remove.update(to:CGPoint(x:2,y:1),keys:keys) == ["K2","K3","K4","Tall","Space"])
        var tap = KeySelectionDrag(tool:.rectangle,start:CGPoint(x:0.5,y:0.5),initial:["K0","Space"],keys:keys)
        assert(tap.update(to:CGPoint(x:0.5,y:0.5),keys:keys) == ["Space"])
        var gap = KeySelectionDrag(tool:.rectangle,start:CGPoint(x:0,y:1.2),initial:["Space"],keys:keys)
        assert(gap.update(to:CGPoint(x:4.9,y:1.8),keys:keys).isEmpty)
        print("PASS: automatic gap drag draws a marquee, key drag paints; brush skips no keys between mouse samples, retracing is idempotent, rectangles shrink/reverse, tall keys hit correctly, Shift adds, Option removes, clicks toggle, gaps select no keys")
    }
}
