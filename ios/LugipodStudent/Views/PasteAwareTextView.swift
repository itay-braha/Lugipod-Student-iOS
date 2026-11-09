import SwiftUI
import UIKit

/// The Lugichat message box: a multi-line text box that also accepts a pasted IMAGE (copied from WhatsApp, Photos, Safari...), the way the
/// Messages app does. A plain SwiftUI `TextField` cannot: it pastes the clipboard's text flavour instead (a file name or "blob"), which is the bug
/// this fixes. A pasted image goes to `onImage`, and the chat shows it as the attached picture above the box (with an x to remove it).
struct PasteAwareTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var maxLines = 5
    var onImage: (UIImage) -> Void

    func makeUIView(context: Context) -> PasteTextView {
        let v = PasteTextView()
        v.delegate = context.coordinator
        v.backgroundColor = .clear
        v.font = Heebo.uiFont(16, 500)
        v.textColor = UIColor(Theme.ink)
        v.textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        v.textContainer.lineFragmentPadding = 0
        v.isScrollEnabled = false
        v.returnKeyType = .default
        v.autocorrectionType = .default
        v.accessibilityIdentifier = "lugichat-input"
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.onImage = onImage
        return v
    }

    func updateUIView(_ v: PasteTextView, context: Context) {
        v.onImage = onImage
        if v.text != text { v.text = text }
        if focused, !v.isFirstResponder { DispatchQueue.main.async { v.becomeFirstResponder() } }
        if !focused, v.isFirstResponder { DispatchQueue.main.async { v.resignFirstResponder() } }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView v: PasteTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 280
        let line = v.font?.lineHeight ?? 20
        let maxHeight = line * CGFloat(maxLines) + 20
        let natural = v.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        v.isScrollEnabled = natural > maxHeight
        return CGSize(width: width, height: min(max(natural, line + 20), maxHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: PasteAwareTextView
        init(_ parent: PasteAwareTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidBeginEditing(_ textView: UITextView) { if !parent.focused { parent.focused = true } }
        func textViewDidEndEditing(_ textView: UITextView) { if parent.focused { parent.focused = false } }
    }
}

/// Takes the pasted picture when the clipboard holds one; otherwise pastes text as usual.
final class PasteTextView: UITextView {
    var onImage: ((UIImage) -> Void)?

    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        if board.hasImages, let image = board.image {
            onImage?(image)
            return
        }
        super.paste(sender)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }
}
