import SwiftUI
import UIKit

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        // Setup ScrollView
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0 // Max zoom 4x
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear // Transparent
        
        // Host Content
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostedView.backgroundColor = .clear
        
        scrollView.addSubview(hostedView)
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // Update Content
        context.coordinator.hostingController.rootView = self.content
        
        // Ensure content size matches (if needed, but HostingController usually handles this)
        // With AutoLayout disabled on hostedView, we rely on intrinsic size or frame.
        // But for Zooming, we usually want the content to be the size of the container initially?
        // Actually, let's explicitely set frame in Coordinator if needed, but usually HostingController does okay.
        // Wait, for Zooming to work, the content view needs a defined size.
        // ReaderPageView uses GeometryReader, so it fills the parent.
        // So we need to make sure the hostedView fills the scrollView.
        
        if let hostedView = uiView.subviews.first {
             hostedView.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(hostingController: UIHostingController(rootView: self.content))
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>
        
        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController.view
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Optional: Center content when zoomed out or smaller than bounds
            // This is effectively handled by the constraints/frame usually?
        }
    }
}
