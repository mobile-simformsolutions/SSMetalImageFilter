//
//  FilterViewController.swift
//  SSMetalImageFilter
//
//  Created by Vishva Bhatt on 10/04/21.
//

import UIKit
import MetalKit

enum PhotoTest : String {
    case workPlay = "WorkPlay"
    case tropical = "TestImage"

}

class FilterViewController: UIViewController {
    
    //MARK: Outlets
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var saturationSlider: UISlider!
    @IBOutlet weak var modeSegment: UISegmentedControl!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var metalView: MTKView!
    
    //MARK: Metal resources
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var sourceTexture: MTLTexture!
    
    
    //MARK: Core Image resources
    var context: CIContext!
    let inputImageViewImage = CIImage()
    let saturationFilter = CIFilter(name: "CIColorControls")
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    var inputImageURL : URL!
    var currentImage : PhotoTest = PhotoTest.workPlay
    
    //MARK: View Life Cycle
    override func viewDidLoad() {
        self.setupMetal()
    }

    //MARK: User defined methods
    func setupMetal(){
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        
        metalView.delegate = self
        metalView.device = device
        metalView.framebufferOnly = false
        
        context = CIContext(mtlDevice: device)
        
        // load texture as an MTL Texture
        let loader = MTKTextureLoader(device: device)
        guard let url = Bundle.main.url(forResource: currentImage.rawValue, withExtension: "jpg"), let image = UIImage(named: "\(currentImage.rawValue).jpg") else {
            return
        }
        inputImageURL = url;
        self.imageView.image = image
        // simulator shows this upside down, real devices show real way up
        #if targetEnvironment(simulator)
        sourceTexture = try! loader.newTexture(URL: url,
                                               options: [:])
        #else
        sourceTexture = try! loader.newTexture(URL: url,
                                               options: [MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically])
        #endif
        self.metalView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    }
    
    func handleViewStates(isUserInteractionEnabled:Bool=false) {
        DispatchQueue.main.async {
            if (isUserInteractionEnabled == false) {
                self.activityIndicator.startAnimating()
                
            }else {
                self.activityIndicator.stopAnimating()
            }
        }
    }
    
    //MARK: Actions
    @IBAction func saturationSliderChanges(_ sender: UISlider) {
        if (self.modeSegment.selectedSegmentIndex == 1) {
            let valueofSlider = sender.value
            DispatchQueue.global(qos: .userInitiated).async {[weak self] in
                guard let self = self else {
                    return
                }
                self.handleViewStates(isUserInteractionEnabled: false)
                if let freshSaturationFilter = self.saturationFilter, let inputImage = CIImage(contentsOf: self.inputImageURL) {
                    freshSaturationFilter.setValue(inputImage, forKey: kCIInputImageKey)
                    freshSaturationFilter.setValue(valueofSlider, forKey: kCIInputSaturationKey)
                    if let output = freshSaturationFilter.outputImage {
                        if let cgimg = self.context.createCGImage(output, from: output.extent) {
                            let processedImage = UIImage(cgImage: cgimg)
                            DispatchQueue.main.async {
                                self.imageView.image = processedImage;
                            }
                            self.handleViewStates(isUserInteractionEnabled: true)
                            
                        }
                    } else {
                        self.handleViewStates(isUserInteractionEnabled: true)
                    }
                } else {
                    self.handleViewStates(isUserInteractionEnabled: true)
                }
            }
        }
    }
    
    @IBAction func defaultAction(_ sender: UIButton) {
        self.saturationSlider.value = 1.0;
        if (self.modeSegment.selectedSegmentIndex == 1) {
            self.saturationSliderChanges(self.saturationSlider)
        }
    }
    
    @IBAction func viewModeChanged(_ sender: UISegmentedControl) {
        self.defaultAction(UIButton())
        self.saturationSlider.isContinuous = sender.selectedSegmentIndex == 0
        self.metalView.isHidden = !(sender.selectedSegmentIndex == 0)
        self.imageView.isHidden = sender.selectedSegmentIndex == 0
        if (sender.selectedSegmentIndex == 1) {
            self.metalView.isPaused = true
        } else {
            self.metalView.isPaused = false
        }
    }
    
    @IBAction func saveImageAction(_ sender: UIButton) {
        guard let outputImage = self.saturationFilter?.outputImage else {
            return
        }
        
        let processedImage = UIImage(ciImage: outputImage, scale: 1, orientation: UIImage.Orientation.downMirrored)
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let filePath = paths.first?.appendingPathComponent("FilteredImage.jpg") {
            print("Output Path \(filePath)")
            if FileManager.default.fileExists(atPath: filePath.path) {
                try? FileManager.default.removeItem(atPath: filePath.path)
            }
            do {
                try processedImage.jpegData(compressionQuality: 0.8)?.write(to: filePath, options: .atomic)
            } catch {
                // Handle the error
            }
        }
    }
    
}
//MARK: Confirmed Delegation

extension FilterViewController: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        if let currentDrawable = view.currentDrawable, let sourceTexture = sourceTexture , let commandBuffer = commandQueue.makeCommandBuffer(), let inputImage = CIImage(mtlTexture: sourceTexture), let saturationFilter = saturationFilter {
    
            // you can chain multiple filters here
            saturationFilter.setValue(inputImage, forKey: kCIInputImageKey)
            saturationFilter.setValue(saturationSlider.value as NSNumber, forKey: kCIInputSaturationKey)
            
            let bounds = CGRect(x: 0, y: 0, width: view.drawableSize.width, height: view.drawableSize.height)
            
            let scaleX = view.drawableSize.width / inputImage.extent.width
            let scaleY = view.drawableSize.height / inputImage.extent.height
            var scale : CGFloat = 1.0
            scale = (scaleY > scaleX) ? min(scaleX, scaleY) : max(scaleX, scaleY)
            
            let width = inputImage.extent.width * scale
            let height = inputImage.extent.height * scale
            let originX = (bounds.width - width) / 2
            let originY = (bounds.height - height) / 2
            
            if let saturationOutput = saturationFilter.outputImage {
                    let scaledImage = saturationOutput
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                        .transformed(by: CGAffineTransform(translationX: originX < 0 ? 0 : originX, y: originY < 0 ? 0 : originY))
                
                context.render(scaledImage,
                               to: currentDrawable.texture,
                               commandBuffer: commandBuffer,
                               bounds: bounds,
                               colorSpace: colorSpace)
                
                commandBuffer.present(currentDrawable)
                commandBuffer.commit()
            }
        }
    }
}
