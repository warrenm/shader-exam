
import Foundation
import MetalKit

struct Uniforms {
    let modelViewMatrix: float4x4
    let projectionMatrix: float4x4
}

class Renderer : NSObject, MTKViewDelegate {
    
    let view: MTKView
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let mainRenderPipeline: MTLRenderPipelineState?
    let postRenderPipeline: MTLRenderPipelineState?
    let depthStencilState: MTLDepthStencilState
    var mesh: MTKMesh?
    var texture: MTLTexture?
    var targets: [MTLTexture] = []
    
    init(view: MTKView, device: MTLDevice) {
        self.view = view
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        
        guard let modelURL = Bundle.main.url(forResource: "pikachu", withExtension: "obj", subdirectory: "pikachu") else {
            fatalError("Could not find model file in main bundle")
        }
        
        let mdlVertexDescriptor = MDLVertexDescriptor()
        mdlVertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: MDLVertexFormat.float3, offset: 0, bufferIndex: 0)
        mdlVertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: MDLVertexFormat.float3, offset: 12, bufferIndex: 0)
        mdlVertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: MDLVertexFormat.float2, offset: 24, bufferIndex: 0)
        mdlVertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: 32)
        
        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        let mdlAsset = MDLAsset(url: modelURL, vertexDescriptor: mdlVertexDescriptor, bufferAllocator: bufferAllocator)
        
        if let firstMDLMesh = mdlAsset.childObjects(of: MDLMesh.self).first as? MDLMesh {
            mesh = try? MTKMesh(mesh: firstMDLMesh, device: device)
        }
        
        guard let textureURL = Bundle.main.url(forResource: "pikachu", withExtension: "png", subdirectory: "pikachu") else {
            fatalError("Could not find model texture file in main bundle")
        }
        
        let textureLoader = MTKTextureLoader(device: device)
        
        let textureOptions = [ MTKTextureLoader.Option.SRGB : false,
                               MTKTextureLoader.Option.origin : MTKTextureLoader.Origin.flippedVertically ] as [MTKTextureLoader.Option : Any]
        texture = try? textureLoader.newTexture(URL: textureURL, options: textureOptions)
        
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load default Metal library from main bundle")
        }
        
        guard let vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlVertexDescriptor) else {
            fatalError("Could not form MTL vertex descriptor from MDL vertex descriptor")
        }
        
        let mainRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
        mainRenderPipelineDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        mainRenderPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        mainRenderPipelineDescriptor.vertexDescriptor = vertexDescriptor
        mainRenderPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        mainRenderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        
        mainRenderPipeline = try? device.makeRenderPipelineState(descriptor: mainRenderPipelineDescriptor)
        
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        let quadVertexDescriptor = MTLVertexDescriptor()
        quadVertexDescriptor.attributes[0].format = .float2
        quadVertexDescriptor.attributes[0].offset = 0
        quadVertexDescriptor.attributes[0].bufferIndex = 0
        quadVertexDescriptor.attributes[1].format = .float2
        quadVertexDescriptor.attributes[1].offset = 8
        quadVertexDescriptor.attributes[1].bufferIndex = 0
        quadVertexDescriptor.layouts[0].stride = 16
        
        let postRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
        postRenderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        postRenderPipelineDescriptor.vertexDescriptor = quadVertexDescriptor
        postRenderPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_post")
        postRenderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_post")
        
        postRenderPipeline = try? device.makeRenderPipelineState(descriptor: postRenderPipelineDescriptor)
    }
    
    func makeOffscreenTargets(_ size: CGSize) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .invalid,
                                                                  width: Int(size.width),
                                                                  height: Int(size.height),
                                                                  mipmapped: false)
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .managed
        let colorTarget = device.makeTexture(descriptor: descriptor)!

        descriptor.pixelFormat = .depth32Float
        descriptor.usage = .renderTarget
        descriptor.storageMode = .`private`
        let depthTarget = device.makeTexture(descriptor: descriptor)!
        
        targets = [colorTarget, depthTarget]
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        makeOffscreenTargets(size)
    }
    
    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let mesh = mesh else { return }
        
        let mainPassDescriptor = MTLRenderPassDescriptor()
        mainPassDescriptor.colorAttachments[0].texture = targets[0]
        mainPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
        mainPassDescriptor.colorAttachments[0].loadAction = .clear
        mainPassDescriptor.colorAttachments[0].storeAction = .store
        mainPassDescriptor.depthAttachment.texture = targets[1]
        mainPassDescriptor.depthAttachment.clearDepth = 1.0
        mainPassDescriptor.depthAttachment.loadAction = .clear
        mainPassDescriptor.depthAttachment.storeAction = .dontCare
        
        guard let mainCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: mainPassDescriptor) else { return }

        mainCommandEncoder.setDepthStencilState(depthStencilState)
        
        if let renderPipeline = mainRenderPipeline {
            mainCommandEncoder.setRenderPipelineState(renderPipeline)
        }

        for (index, vertexBuffer) in mesh.vertexBuffers.enumerated() {
            mainCommandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: index)
        }
        
        if let texture = texture {
            mainCommandEncoder.setFragmentTexture(texture, index: 0)
        }
        
        let modelTransform = float4x4(translationBy: float3(0, -1.1, 0)) * float4x4(scaleBy: Float(1 / 4.5))
        let cameraTransform = float4x4(translationBy: float3(0, 0, -4))
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        let projectionMatrix = float4x4(perspectiveProjectionFov: .pi / 6, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100)
        var uniforms = Uniforms(modelViewMatrix: cameraTransform * modelTransform, projectionMatrix: projectionMatrix)
        
        mainCommandEncoder.setVertexBytes(&uniforms, length: MemoryLayout.size(ofValue: uniforms), index: 1)
        
        if let submesh = mesh.submeshes.first {
            let indexBuffer = submesh.indexBuffer
            mainCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                     indexCount: submesh.indexCount,
                                                     indexType: submesh.indexType,
                                                     indexBuffer: indexBuffer.buffer,
                                                     indexBufferOffset: indexBuffer.offset)
        }
        
        mainCommandEncoder.endEncoding()
        
        guard let postRenderPassDescriptor = view.currentRenderPassDescriptor else { return }
        guard let postCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: postRenderPassDescriptor) else { return }
        
        if let renderPipeline = postRenderPipeline {
            postCommandEncoder.setRenderPipelineState(renderPipeline)
        }
        
        postCommandEncoder.setFragmentTexture(targets[0], index: 0)
        
        let vertexData: [Float] = [
            -1, -1, 0, 1,
            -1,  1, 0, 0,
             1, -1, 1, 1,
             1,  1, 1, 0,
        ]
        
        postCommandEncoder.setVertexBytes(vertexData, length: 16 * 4, index: 0)
        
        postCommandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        postCommandEncoder.endEncoding()
        
        guard let drawable = view.currentDrawable else { return }
        commandBuffer.present(drawable)
        
        commandBuffer.commit()
    }
}
