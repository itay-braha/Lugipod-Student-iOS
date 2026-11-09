import SwiftUI
import UIKit

/// Any picture in the app opens full screen when tapped: pinch to zoom, double-tap to zoom in and out, drag to move, the x (or a swipe down
/// on the close button area) to close. Use `.tapToZoom(image)` on the small picture.
struct ImageViewerScreen: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ZoomableImage(image: image).ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(.white, .black.opacity(0.55))
                    .padding(16)
            }
            .accessibilityLabel("סגירה")
        }
        .statusBarHidden()
    }
}

/// A scroll view that zooms its picture (1x to 5x) and re-centres it.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scroll.addSubview(imageView)
        scroll.imageView = imageView
        context.coordinator.imageView = imageView

        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(double)
        return scroll
    }

    func updateUIView(_ scroll: ZoomScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView, let imageView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

final class ZoomScrollView: UIScrollView {
    weak var imageView: UIImageView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let imageView else { return }
        if zoomScale <= 1.001 {
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }
}

private struct TapToZoom: ViewModifier {
    let image: UIImage?
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { if image != nil { show = true } }
            .accessibilityAddTraits(image == nil ? [] : .isButton)
            .accessibilityHint(image == nil ? "" : "לחצו להגדלה")
            .fullScreenCover(isPresented: $show) {
                if let image { ImageViewerScreen(image: image) }
            }
    }
}

extension View {
    /// Tapping this view opens the picture full screen, zoomable.
    func tapToZoom(_ image: UIImage?) -> some View { modifier(TapToZoom(image: image)) }
}
