import AppKit

@objc(VCDelegate)
protocol VCDelegate: NSObjectProtocol {
    func update(_ controller: AAPLViewController)
    func viewController(_ viewController: AAPLViewController, willPause pause: Bool)
}

var vc:AAPLViewController!

@objc(AAPLViewController)
class AAPLViewController: NSViewController {

    weak var delegate: VCDelegate?
    private(set) var timeSinceLastDraw: TimeInterval = 0.0

    var interval: Int = 0
    var _displayLink: CVDisplayLink?
    var _displaySource: DispatchSourceUserDataAdd?
    private var _firstDrawOccurred: Bool = false
    private var _timeSinceLastDrawPreviousTime: CFTimeInterval = 0.0
    private var _gameLoopPaused: Bool = false
    private var _renderer: Renderer!

    @IBAction func speedSliderChanged(_ sender: NSSlider) {
        aDiff = Float(0.0002) + sender.floatValue * Float(0.002)
    }

    deinit {
        if _displayLink != nil {
            self.stopGameLoop()
        }
    }

    private let dispatchGameLoop: CVDisplayLinkOutputCallback = {
        displayLink, now, outputTime, flagsIn, flagsOut, displayLinkContext in

        let source = Unmanaged<DispatchSourceUserDataAdd>.fromOpaque(displayLinkContext!).takeUnretainedValue()
        source.add(data: 1)
        return kCVReturnSuccess
    }

    private func initCommon() {
        vc = self
        _renderer = Renderer()
        self.delegate = _renderer

        _displaySource = DispatchSource.makeUserDataAddSource(queue: .main)
        _displaySource!.setEventHandler {[weak self] in
            self?.gameloop()
        }
        _displaySource!.resume()

        var cvReturn = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink)
        assert(cvReturn == kCVReturnSuccess)

        cvReturn = CVDisplayLinkSetOutputCallback(_displayLink!, dispatchGameLoop, Unmanaged.passUnretained(_displaySource!).toOpaque())
        assert(cvReturn == kCVReturnSuccess)

        cvReturn = CVDisplayLinkSetCurrentCGDisplay(_displayLink!, CGMainDisplayID())
        assert(cvReturn == kCVReturnSuccess)

        interval = 1
    }

    @objc func _windowWillClose(_ notification: Notification) {
        if notification.object as AnyObject? === self.view.window {
            CVDisplayLinkStop(_displayLink!)
            _displaySource!.cancel()
        }
    }

    override init?(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.initCommon()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initCommon()
    }

    @IBOutlet weak var renderView: AAPLView!

    override func viewDidLoad() {
        super.viewDidLoad()

        renderView.delegate = _renderer
        _renderer.configure(renderView)

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(_windowWillClose),  name: .NSWindowWillClose, object: self.view.window)
        CVDisplayLinkStart(_displayLink!)
    }

    @objc func gameloop() {
        delegate?.update(self)
        renderView.display()
    }

    func stopGameLoop() {
        if _displayLink != nil {
            CVDisplayLinkStop(_displayLink!)
            _displaySource!.cancel()

            _displayLink = nil
            _displaySource = nil
        }
    }

    var paused: Bool {
        get {
            return _gameLoopPaused
        }
        set {
            if _gameLoopPaused == newValue {
                return
            }

            if _displayLink != nil {
                // inform the delegate we are about to pause
                delegate?.viewController(self, willPause: newValue)

                if newValue {
                    CVDisplayLinkStop(_displayLink!)
                } else {
                    CVDisplayLinkStart(_displayLink!)
                }
            }
        }
    }

    @objc func didEnterBackground(_ notification: Notification) {
        self.paused = true
    }

    @objc func willEnterForeground(_ notification: Notification) {
        self.paused = false
    }
}
