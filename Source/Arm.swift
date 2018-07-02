import MetalKit
import SceneKit

class CircleData {
    var pos = float3()
    var dist = Float()
    var angle = float2()
    var width = Float()
    init(_ nwidth:Float, _ ndist:Float) { width = nwidth; dist = ndist }
}

let ARM_MAX_CIRCLE = 165        // arm length
let ATOUCH = ARM_MAX_CIRCLE-6   // which am data entry IK is trying to move to position
let NUM_GENTRY = 20             // #positions along arm length where IK is performed

var aDiff:Float = 0.001         // arm movement amount
var cd = [CircleData]()
var style:MTLPrimitiveType = .line
var target:float3 = float3(1,14,0)

class GoalEntry {
    var cIndex:Int = 1              // which circle entry we affect
    var angle:float2 = float2(0,0)  // current angle

    init(_ ncIndex:Int) {
        cIndex = ncIndex
        assert(cIndex < ARM_MAX_CIRCLE - 2)
    }

    func rotateCAngle(_ index:Int) {
        cd[cIndex].angle = angle

        switch index {
        case 1 : cd[cIndex].angle.x += aDiff
        case 2 : cd[cIndex].angle.x -= aDiff
        case 3 : cd[cIndex].angle.y += aDiff
        case 4 : cd[cIndex].angle.y -= aDiff
        default : break
        }
    }

    func rotateAngle(_ index:Int) {
        switch index {
        case 1 : angle.x += aDiff
        case 2 : angle.x -= aDiff
        case 3 : angle.y += aDiff
        case 4 : angle.y -= aDiff
        default : break
        }

        var ha = angle/2
        cd[cIndex-1].angle = ha
        cd[cIndex+1].angle = ha
        ha = angle/4
        cd[cIndex-2].angle = ha
        cd[cIndex+2].angle = ha
    }

    func relax() {
        angle *= 0.99
    }
}

var gEntry:[GoalEntry] = []

class Goal {

    init() {
        let hop = (ARM_MAX_CIRCLE-2) / NUM_GENTRY
        for i in 0 ..< NUM_GENTRY {
            let index = 3 + i * hop
            gEntry.append(GoalEntry(index))
            cData[index].color = float4(1,1,0,1)
        }

        cData[0].color = float4(0,0,1,1)
    }

    func distance3D(_ pos:float3) -> Float {
        let d = target - pos
        return sqrtf(d.x * d.x + d.y * d.y + d.z * d.z)
    }

    func moveToBestRotation(_ index:Int) {
        let NUM_ROTATION_STYLES = 5 // none, +-X, +-Y
        var bestDistance:Float = 99999
        var bestIndex:Int = 0

        for i in 0 ..< NUM_ROTATION_STYLES {
            gEntry[index].rotateCAngle(i)
            arm.updateCirclePositions()

            let tPos = cd[ATOUCH].pos
            let dist = distance3D(tPos)

            if dist < bestDistance {
                bestDistance = dist
                bestIndex = i
            }
        }

        gEntry[index].rotateAngle(bestIndex)
    }

    func update() {
        for i in 0 ..< NUM_GENTRY {
            gEntry[i].relax()

            for j in stride(from:i, through:NUM_GENTRY-1, by: 2) {
                moveToBestRotation(j)
            }
        }

        arm.updateCirclePositions()
        arm.updateDefinition()

        let tPos = cd[ATOUCH].pos       // touched target? move T to ramdom position
        let dist = distance3D(tPos)
        if dist < 0.25 {
            target.x = 1 + 15 * Float(arc4random() & 1023) / 1024
            target.y = 1 + 15 * Float(arc4random() & 1023) / 1024
            target.z = 1 + 15 * Float(arc4random() & 1023) / 1024
        }
    }
}

let goal = Goal()
var cData = [TVertex]()    // circle points

class Arm {
    var cBuffer: MTLBuffer?
    var vBuffer: MTLBuffer?
    var iBuffer: MTLBuffer?
    var vData = [TVertex]()    // vertices
    var iData = [UInt16]()     // indices
    var numSides:Int = 32
    var autoAngle:Float = 0
    var baseYrot:Float = 0

    init(_ baseAngle:Float) {
        reset(baseAngle)
    }

    //MARK: -

    func update() { goal.update() }

    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        if vData.count == 0 { return }

        renderEncoder.setVertexBuffer(vBuffer, offset: 0, at: 0)
        renderEncoder.drawIndexedPrimitives(type:style, indexCount: iData.count, indexType: MTLIndexType.uint16, indexBuffer: iBuffer!, indexBufferOffset:0)

        let cC = style == .line ? cData.count-1 : 1
            renderEncoder.setVertexBuffer(cBuffer, offset: 0, at: 0)
            renderEncoder.drawPrimitives(type: .point, vertexStart:0, vertexCount:cC)
    }

    func reset(_ baseAngle:Float) {
        baseYrot = baseAngle
        autoAngle = baseAngle / 10
        defineMesh()
    }

    func defineMesh()  {
        cd.removeAll()
        cData.removeAll()

        var sz = Float(3)
        for i in 0 ..< ARM_MAX_CIRCLE {
            cd.append(CircleData(sz,0.2))

            cData.append(TVertex())
            cData[i].drawStyle = 0
            cData[i].color = float4(1,0,0,1)

            sz *= 0.98
        }

        updateCirclePositions()
        updateDefinition()
    }

    var aa:Float = 0

    func clampRotation(_ v:Float) -> Float {
        let mx = Float(0.5)
        if v < -mx { return -mx }
        if v > mx  { return mx }
        return v
    }

    func updateCircles() {
        let xAmount:Float = sinf(aa) / 3
        let yAmount:Float = cosf(aa * 1.5) / 3
        let tratio:[Float] = [ 0.1, 0.2, 0.7, 0.9, 1, 0.9, 0.7, 0.2, 0.1 ] // ease in/out ratios

        aa += aDiff

        for ii in 1 ..< cd.count - 10 {
            var index = ii

            for i in 0 ..< 9 {
                cd[index].angle.x = xAmount * tratio[i]
                cd[index].angle.y = yAmount * tratio[i]

                cd[index].angle.x = clampRotation(cd[index].angle.x)
                cd[index].angle.y = clampRotation(cd[index].angle.y)
                index += 1
            }
        }

        updateCirclePositions()
        //Swift.print(String(format:"%5.3f,%5.3f, %5.3f" , cd[199].pos.x,cd[199].pos.y,cd[199].pos.z))
    }

    func rotatePos(_ old:float3, _ angle:float2) -> float3 {
        var pos = old

        var qt = pos.x  // X rotation
        pos.x = pos.x * cosf(angle.x) - pos.y * sinf(angle.x)
        pos.y = qt * sinf(angle.x) + pos.y * cosf(angle.x)

        qt = pos.x      // Y rotation
        pos.x = pos.x * cosf(angle.y) - pos.z * sinf(angle.y)
        pos.z = qt * sinf(angle.y) + pos.z * cosf(angle.y)

        return pos
    }

    func updateCirclePositions() {
        var currentAngle = float2(0,baseYrot)
        for i in 0 ..< cd.count {
            currentAngle += cd[i].angle
            cd[i].pos = rotatePos(float3(cd[0].dist,0,0), currentAngle)
            if i > 0 { cd[i].pos += cd[i-1].pos }
            cData[i].pos = cd[i].pos
        }
    }

    func updateDefinition() {
        let tCount = cd.count * numSides

        vData.removeAll()
        for i in 0 ..< tCount {
            vData.append(TVertex())
            vData[i].color = float4(1,1,1,1)
            vData[i].drawStyle = (style == .line) ? 0 : 1
        }

        var currentAngle = float2(0,baseYrot)

        for ci in 0 ..< cd.count {
            let cRef = cd[ci]
            let tBaseIndex = ci * numSides

            currentAngle += cd[ci].angle

            var angle = Float(0)
            let angleHop = Float( Float(Double.pi * 2.0) / Float(numSides))
            let txtY:Float = Float(ci) / Float(cd.count)

            for i in 0 ..< numSides {
                // unrotated 'resting' position
                vData[tBaseIndex + i].pos = float3(0, cosf(angle) * cRef.width, sinf(angle) * cRef.width)
                angle += angleHop

                // rotated by current accumulated angle
                vData[tBaseIndex + i].pos = rotatePos(vData[tBaseIndex + i].pos,currentAngle)

                // offset by parent's final position
                if ci > 0 { vData[tBaseIndex + i].pos += cd[ci-1].pos }

                vData[tBaseIndex + i].txt.x = Float(i) / Float(numSides)
                vData[tBaseIndex + i].txt.y = txtY
            }
        }

        cData[0].pos = target

        cBuffer = gDevice?.makeBuffer(bytes: cData,  length: cData.count  * MemoryLayout<TVertex>.size, options: MTLResourceOptions())

        // indices -------------------------------------
        iData.removeAll()

        if style == .line {
            for c in 0 ..< cd.count {
                let base = c * numSides

                for i in 0 ..< numSides {
                    var i2 = i+1
                    if i2 == numSides { i2 = 0 }

                    iData.append(UInt16(base+i))
                    iData.append(UInt16(base+i2))

                    if c < cd.count-1 {
                        i2 = i + numSides
                        iData.append(UInt16(base+i))
                        iData.append(UInt16(base+i2))
                    }
                }
            }
        }

        if style == .triangle {
            for c in 0 ..< cd.count-1 {
                let base = c * numSides

                for i in 0 ..< numSides {
                    var i2 = i+1
                    if i2 == numSides { i2 = 0 }
                    let i3 = i + numSides
                    let i4 = i2 + numSides
                    iData.append(UInt16(base+i))
                    iData.append(UInt16(base+i2))
                    iData.append(UInt16(base+i3))
                    iData.append(UInt16(base+i2))
                    iData.append(UInt16(base+i4))
                    iData.append(UInt16(base+i3))
                }
            }

            // calc normals
            var index = 0
            while true {
                let i1 = Int(iData[index])
                let i2 = Int(iData[index+1])
                let i3 = Int(iData[index+2])
                let tp1 = vData[i1]
                let tp2 = vData[i2]
                let tp3 = vData[i3]
                let p1 = tp1.pos
                let p2 = tp2.pos
                let p3 = tp3.pos
                let t1 = p2 - p1
                let t2 = p3 - p1

                var n = float3()
                n.x = (t1.y * t2.z) - (t2.y * t1.z)
                n.y = (t1.z * t2.x) - (t2.z * t1.x)
                n.z = (t1.x * t2.y) - (t2.x * t1.y)
                vData[i1].nrm = normalize(n)

                index += 3
                if index >= iData.count - 2 { break }
            }
        }

        vBuffer = gDevice?.makeBuffer(bytes: vData,  length: vData.count  * MemoryLayout<TVertex>.size, options: MTLResourceOptions())
        iBuffer = gDevice?.makeBuffer(bytes: iData, length: iData.count * MemoryLayout<UInt16>.size,  options: MTLResourceOptions())
    }
}
