import AppKit
import MetalKit
import simd

let world = World()

var gDevice: MTLDevice?
var gQueue: MTLCommandQueue?

var _projectionMatrix = float4x4()
var translationAmount = Float(10)

var tVertexSize: Int = MemoryLayout<TVertex>.stride

var constants: [MTLBuffer] = []
var constantsSize: Int = MemoryLayout<ConstantData>.stride
var constantsIndex: Int = 0

func alterTranslationAmount(_ amt:Float) {
    translationAmount += amt
    if translationAmount < 2 { translationAmount = 2 } else if translationAmount > 80 { translationAmount = 80 }
}

func updateDrawStyle(_ renderEncoder:MTLRenderCommandEncoder, _ drawStyle:UInt8) {
   if drawStyle != constantData.drawStyle {
        constantData.drawStyle = drawStyle

        let constant_buffer = constants[constantsIndex].contents().assumingMemoryBound(to: ConstantData.self)
        constant_buffer[0].drawStyle = drawStyle
        renderEncoder.setVertexBuffer(constants[constantsIndex], offset:0, at: 1)
    }
}

class Renderer: NSObject, VCDelegate, VDelegate {
    private let kInFlightCommandBuffers = 3
    private var semaphore:DispatchSemaphore!
    private var _pipelineState: MTLRenderPipelineState?
    private var _depthState: MTLDepthStencilState?
    var png2:MTLTexture!
    var samplerState:MTLSamplerState!

    override init() {
        super.init()
        semaphore = DispatchSemaphore(value: kInFlightCommandBuffers)
    }

    //MARK: - Configure

    func configure(_ view: AAPLView) {

       // Swift.print("ConstantSize = ",constantsSize,",  TVertex Size = ",tVertexSize )

        gDevice = view.device
        guard let gDevice = gDevice else { fatalError("MTL device not found")  }

        view.depthPixelFormat = .depth32Float
        view.stencilPixelFormat = .invalid

        do {
            if #available(OSX 10.12, *) {
                let tLoad = MTKTextureLoader(device:gDevice)
                try png2 = tLoad.newTexture(withName:"p19", scaleFactor:1, bundle: .main, options:nil)
            }
        } catch {
            fatalError("\n\nload txt failed\n\n")
        }

        gQueue = gDevice.makeCommandQueue()

        preparePipelineState(view)

        let depthStateDesc = MTLDepthStencilDescriptor()
        depthStateDesc.depthCompareFunction = .less
        depthStateDesc.isDepthWriteEnabled = true
        _depthState = gDevice.makeDepthStencilState(descriptor: depthStateDesc)

        constants = []
        for _ in 0..<kInFlightCommandBuffers {
            constants.append(gDevice.makeBuffer(length: constantsSize, options: []))
        }

        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .nearest
        sampler.magFilter = .nearest
        sampler.mipFilter = .nearest
        sampler.maxAnisotropy = 1
        sampler.sAddressMode = .repeat
        sampler.tAddressMode = .repeat
        sampler.rAddressMode = .repeat
        sampler.normalizedCoordinates = true
        sampler.lodMinClamp = 0
        sampler.lodMaxClamp = .greatestFiniteMagnitude

        samplerState = gDevice.makeSamplerState(descriptor: sampler)
    }

    func preparePipelineState(_ view: AAPLView) {
        guard let _defaultLibrary = gDevice!.newDefaultLibrary() else { NSLog(">> ERROR: Couldnt create a default shader library"); fatalError() }
        guard let vertexProgram = _defaultLibrary.makeFunction(name: "texturedVertexShader") else { NSLog("V shader load"); fatalError() }
        guard let fragmentProgram = _defaultLibrary.makeFunction(name: "texturedFragmentShader") else { NSLog("F shader load"); fatalError() }

        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label  = "MyPipeline"
        pipelineStateDescriptor.sampleCount = 1
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthPixelFormat

        let psd = pipelineStateDescriptor.colorAttachments[0]!
        psd.pixelFormat = .bgra8Unorm

        //        // alpha blending enable
        //        psd.isBlendingEnabled = true
        //        psd.alphaBlendOperation = .add
        //        psd.rgbBlendOperation = .add
        //        psd.sourceRGBBlendFactor = .sourceAlpha
        //        psd.sourceAlphaBlendFactor = .sourceAlpha
        //        psd.destinationRGBBlendFactor = .oneMinusSourceAlpha
        //        psd.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {  _pipelineState = try gDevice?.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch let error as NSError { NSLog(">> ERROR: Failed Aquiring pipeline state: \(error)"); fatalError() }
    }

    //MARK: - Render

    var lightpos = float3()
    var lAngle = Float(0)

    func render(_ view: AAPLView) {
        _ = semaphore.wait(timeout: .distantFuture)
        let commandBuffer = gQueue?.makeCommandBuffer()
        let renderPassDescriptor = view.renderPassDescriptor
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)

        renderEncoder?.setDepthStencilState(_depthState)
        renderEncoder?.setRenderPipelineState(_pipelineState!)
        if let samplerState = samplerState { renderEncoder?.setFragmentSamplerState(samplerState, at: 0) } else { return }

        // -----------------------------
        let constant_buffer = constants[constantsIndex].contents().assumingMemoryBound(to: ConstantData.self)
        constant_buffer[0].mvp =
            _projectionMatrix
            * translate(-3,0,translationAmount)  //   hardwired X position
            * arcBall.transformMatrix

        lightpos.x = sinf(lAngle) * 5
        lightpos.y = 5
        lightpos.z = cosf(lAngle) * 5
        lAngle += 0.01
        constant_buffer[0].light = normalize(lightpos)

        renderEncoder?.setVertexBuffer(constants[constantsIndex], offset:0, at: 1)
        renderEncoder?.setFragmentTexture(png2, at: 0)

        ///////////////////////////////////////////////
        world.render(renderEncoder!)
        ///////////////////////////////////////////////

        renderEncoder?.endEncoding()
        commandBuffer?.present(view.currentDrawable!)

        let block_sema = semaphore!
        commandBuffer?.addCompletedHandler{ buffer in block_sema.signal() }

        commandBuffer?.commit()
        constantsIndex = (constantsIndex + 1) % kInFlightCommandBuffers
    }

    func reshape(_ view: AAPLView) {
        let kFOVY: Float = 65.0
        let aspect = Float(abs(view.bounds.size.width / view.bounds.size.height))
        _projectionMatrix = perspective_fov(kFOVY, aspect, 0.1, 100.0)

        arcBall.initialize(Float(view.bounds.size.width),Float(view.bounds.size.height))
    }

    //MARK: - Update

    func mouseControl(_ dx:Float, _ dy:Float, _ dZoom:Float) {
        alterTranslationAmount(dZoom/10)
        arcBall.mouseDown(CGPoint(x:CGFloat(500), y:CGFloat(500)))
        arcBall.mouseMove(CGPoint(x:CGFloat(500+dx), y:CGFloat(500-dy)))
    }

    func keyCharacter(_ ch:String) { world.keyCharacter(ch) }
    func update(_ controller: AAPLViewController) { world.update(controller) }
    func viewController(_ viewController: AAPLViewController, willPause pause: Bool) {}
}
