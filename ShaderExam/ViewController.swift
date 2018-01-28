
import Cocoa
import MetalKit

class ViewController: NSViewController {
    
    let mtkView = MTKView()
    let device = MTLCreateSystemDefaultDevice()!
    var renderer: Renderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(mtkView)
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints(
            NSLayoutConstraint.constraints(withVisualFormat: "|[view]|", options: [], metrics: nil, views: ["view" : mtkView]) +
                NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|", options: [], metrics: nil, views: ["view" : mtkView])
        )
        
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        
        renderer = Renderer(view: mtkView, device: device)
        mtkView.delegate = renderer
    }
}

