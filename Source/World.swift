import AppKit
import Metal
import simd

var arm = Arm(0)
var constantData = ConstantData()
var dirty = true

class World {
    func update(_ controller: AAPLViewController) { arm.update() }
    func render(_ renderEncoder:MTLRenderCommandEncoder) { arm.render(renderEncoder) }

    func keyCharacter(_ ch:String) {
        switch ch {
            case " " : style = (style == .line) ? .triangle : .line
            default : break
        }

        dirty = true
    }
}

