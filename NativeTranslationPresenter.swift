import UIKit
import SwiftUI
import Translation
import ObjectiveC

@objc(NativeTranslationPresenter)
final class NativeTranslationPresenter: NSObject {
    private static var activeHostKey: UInt8 = 0

    @objc static func canPresentNativeTranslation() -> Bool {
        if #available(iOS 17.4, *) {
            return true
        }
        return false
    }

    @objc static func present(fromViewController viewController: UIViewController, text: String, sourceView: UIView?) {
        guard #available(iOS 17.4, *) else { return }

        if let existingHost = objc_getAssociatedObject(viewController, &activeHostKey) as? UIViewController {
            existingHost.willMove(toParent: nil)
            existingHost.view.removeFromSuperview()
            existingHost.removeFromParent()
        }

        var hostingController: UIHostingController<NativeTranslationHostView>!
        let rootView = NativeTranslationHostView(text: text) {
            hostingController?.willMove(toParent: nil)
            hostingController?.view.removeFromSuperview()
            hostingController?.removeFromParent()
            objc_setAssociatedObject(viewController, &activeHostKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isUserInteractionEnabled = false

        viewController.addChild(hostingController)
        viewController.view.addSubview(hostingController.view)

        if let sourceView {
            let frame = sourceView.convert(sourceView.bounds, to: viewController.view)
            hostingController.view.frame = frame
        } else {
            hostingController.view.frame = viewController.view.bounds
        }

        hostingController.didMove(toParent: viewController)
        objc_setAssociatedObject(viewController, &activeHostKey, hostingController, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

@available(iOS 17.4, *)
private struct NativeTranslationHostView: View {
    let text: String
    let onTranslationDismissed: () -> Void

    @State private var showTranslation = false
    @State private var didAutopresent = false

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .translationPresentation(
                isPresented: $showTranslation,
                text: text,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom,
                replacementAction: nil
            )
            .task {
                guard !didAutopresent else { return }
                didAutopresent = true
                await MainActor.run {
                    showTranslation = true
                }
            }
            .onChange(of: showTranslation) { _, isPresented in
                if didAutopresent && !isPresented {
                    onTranslationDismissed()
                }
            }
    }
}
