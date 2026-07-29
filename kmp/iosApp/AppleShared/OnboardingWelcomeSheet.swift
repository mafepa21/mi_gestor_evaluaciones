import SwiftUI

/// Bienvenida de primer uso. Se lee en veinte segundos: qué es la app, las tres
/// cosas que hace, y una única acción destacada para empezar a configurarla.
///
/// No es un tutorial paso a paso a pantalla completa: el recorrido real vive en
/// `OnboardingChecklistView`, que se puede dejar a medias y retomar otro día.
struct OnboardingWelcomeSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    let onStart: () -> Void
    let onSkip: () -> Void

    private struct Highlight: Identifiable {
        let id = UUID()
        let systemImage: String
        let title: String
        let detail: String
        let tint: Color
    }

    private let highlights: [Highlight] = [
        .init(
            systemImage: "calendar",
            title: "Planifica",
            detail: "Tu horario semanal, las sesiones de cada día y la secuencia del trimestre.",
            tint: .blue
        ),
        .init(
            systemImage: "tablecells",
            title: "Evalúa",
            detail: "Cuaderno de notas, rúbricas e instrumentos ligados a tus situaciones de aprendizaje.",
            tint: .indigo
        ),
        .init(
            systemImage: "person.3",
            title: "Sigue a tu grupo",
            detail: "Asistencia, perfiles de alumnado, informes y copias de seguridad.",
            tint: .teal
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    VStack(spacing: 14) {
                        ForEach(highlights) { highlight in
                            highlightRow(highlight)
                        }
                    }
                    nextStepNote
                }
                .padding(28)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            Divider()
            footer
        }
        .background(appPageBackground(for: colorScheme))
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 560, idealHeight: 640)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(EvaluationDesign.accent)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(EvaluationDesign.accent.opacity(0.12))
                )
                .accessibilityHidden(true)

            Text("Bienvenido a MiGestor")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Tu curso entero en un sitio: horario, cuaderno, asistencia y evaluación. Antes de empezar, vamos a dejar configurado lo mínimo para que la app te sirva desde mañana.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func highlightRow(_ highlight: Highlight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: highlight.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(highlight.tint)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(highlight.tint.opacity(0.14))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(highlight.title)
                    .font(.headline)
                Text(highlight.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(appCardBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppleDesignSystem.border, lineWidth: 1)
                )
        )
    }

    private var nextStepNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EvaluationDesign.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Son cinco pasos y puedes dejarlos a medias")
                    .font(.subheadline.weight(.semibold))
                Text("Empezamos por las fechas del curso y el horario. Con el horario se crean solos tus grupos. Después, el alumnado. Cada paso se puede importar de un archivo o hacer a mano.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(EvaluationDesign.accent.opacity(0.08))
        )
    }

    private var footer: some View {
        HStack {
            Button("Ahora no", action: onSkip)
                .buttonStyle(.bordered)
                .controlSize(.large)
            Spacer()
            Button("Configurar mi curso", action: onStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(20)
    }
}
