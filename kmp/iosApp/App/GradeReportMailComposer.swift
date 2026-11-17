import Foundation
import SwiftUI
#if os(iOS)
import MessageUI
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Correo de un informe de notas, listo para abrir en Mail.
struct GradeReportMailDraft: Identifiable, Equatable {
    let id = UUID()
    let studentId: Int64
    let recipient: String
    let subject: String
    let body: String
    let attachmentURL: URL
}

/// Qué pasó con el correo tras abrirlo.
enum GradeReportMailOutcome: Equatable {
    /// iPad: el docente pulsó Enviar en la ventana de correo.
    case sent
    /// Mac: el correo quedó abierto en Mail; el envío final ocurre allí.
    case openedInMail
    case cancelled
    case failed
}

enum GradeReportMail {
    /// En iPad hace falta una cuenta configurada en Mail. En Mac siempre se intenta abrir Mail.
    static var canComposeInApp: Bool {
        #if os(iOS)
        return MFMailComposeViewController.canSendMail()
        #else
        return NSSharingService(named: .composeEmail) != nil
        #endif
    }

    #if os(macOS)
    /// Abre un correo nuevo en Mail con destinatario, asunto, texto y PDF adjunto.
    @MainActor
    static func composeInMail(_ draft: GradeReportMailDraft, completion: @escaping (GradeReportMailOutcome) -> Void) {
        guard let service = NSSharingService(named: .composeEmail) else {
            completion(.failed)
            return
        }
        let delegate = MacMailDelegate(completion: completion)
        service.delegate = delegate
        service.recipients = [draft.recipient]
        service.subject = draft.subject
        // El servicio no guarda una referencia fuerte a su delegado.
        MacMailDelegate.active = delegate
        let items: [Any] = [draft.body, draft.attachmentURL]
        if service.canPerform(withItems: items) {
            service.perform(withItems: items)
        } else {
            MacMailDelegate.active = nil
            completion(.failed)
        }
    }

    private final class MacMailDelegate: NSObject, NSSharingServiceDelegate {
        static var active: MacMailDelegate?
        let completion: (GradeReportMailOutcome) -> Void

        init(completion: @escaping (GradeReportMailOutcome) -> Void) {
            self.completion = completion
        }

        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
            completion(.openedInMail)
            Self.active = nil
        }

        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            let cancelled = (error as NSError).code == NSUserCancelledError
            completion(cancelled ? .cancelled : .failed)
            Self.active = nil
        }
    }
    #endif
}

#if os(iOS)
/// Ventana de correo de Apple con el PDF adjunto. Nada se envía hasta que el docente pulsa Enviar.
struct GradeReportMailComposeView: UIViewControllerRepresentable {
    let draft: GradeReportMailDraft
    let onFinish: (GradeReportMailOutcome) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        if let data = try? Data(contentsOf: draft.attachmentURL) {
            controller.addAttachmentData(data, mimeType: "application/pdf", fileName: draft.attachmentURL.lastPathComponent)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (GradeReportMailOutcome) -> Void
        init(onFinish: @escaping (GradeReportMailOutcome) -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            switch result {
            case .sent: onFinish(.sent)
            case .failed: onFinish(.failed)
            default: onFinish(.cancelled)
            }
        }
    }
}
#endif
