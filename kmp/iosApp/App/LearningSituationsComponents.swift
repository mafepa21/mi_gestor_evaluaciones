import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

// Componentes compartidos de Situaciones de Aprendizaje (estado, badge).
extension LearningSituationsWorkspaceView {
    func situationStatusLabel(_ status: LearningSituationStatus) -> String {
        switch status {
        case .draft: return "Borrador"
        case .active: return "Activa"
        case .archived: return "Archivada"
        default: return "Sin estado"
        }
    }

    func situationStatusTint(_ status: LearningSituationStatus) -> Color {
        switch status {
        case .draft: return .secondary
        case .active: return EvaluationDesign.success
        case .archived: return .orange
        default: return .secondary
        }
    }

    func situationStatusBadge(_ status: LearningSituationStatus) -> some View {
        Text(situationStatusLabel(status).uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.4)
            .foregroundStyle(situationStatusTint(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(situationStatusTint(status).opacity(0.12), in: Capsule())
    }
}
