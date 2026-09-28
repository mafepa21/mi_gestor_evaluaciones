import SwiftUI

struct TeacherRadarStudentInsightRow: View {
    let insight: TeacherRadarInsightDraft

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.priority.systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(insight.priority.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(insight.priority.title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(insight.priority.tint)
                    if insight.id.contains("-ml-") {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 8, weight: .bold))
                            Text("CORE ML")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(Color.purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                    }
                    Text(insight.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Text(insight.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if insight.id.contains("-ml-") && !insight.evidence.isEmpty {
                    Text("Factores: " + insight.evidence.joined(separator: " • "))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.purple.opacity(0.85))
                        .lineLimit(2)
                }
                Text(insight.suggestedAction)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if insight.id.contains("-ml-"), let studentId = insight.studentId, let classId = insight.classId {
                let patternType = insight.patternType ?? .silentDisengagement
                Menu {
                    Section("Resolución docente") {
                        Button {
                            PedagogicalMLCalibrationService.shared.setStatus(
                                studentId: studentId,
                                classId: classId,
                                patternType: patternType,
                                status: .addressed,
                                reason: .trackingStarted,
                                note: "Intervención o tutoría iniciada"
                            )
                        } label: {
                            Label("Marcar como atendida (En seguimiento)", systemImage: "checkmark.circle")
                        }

                        Button {
                            PedagogicalMLCalibrationService.shared.setStatus(
                                studentId: studentId,
                                classId: classId,
                                patternType: patternType,
                                status: .dismissed,
                                reason: .personalCircumstance,
                                note: "Circunstancia personal / médica justificada"
                            )
                        } label: {
                            Label("Descartar: Justificado / Médico", systemImage: "cross.case")
                        }

                        Button {
                            PedagogicalMLCalibrationService.shared.setStatus(
                                studentId: studentId,
                                classId: classId,
                                patternType: patternType,
                                status: .dismissed,
                                reason: .falsePositive,
                                note: "Evolución real adecuada (Falso positivo)"
                            )
                        } label: {
                            Label("Descartar: Falso positivo", systemImage: "hand.thumbsup")
                        }

                        Button {
                            PedagogicalMLCalibrationService.shared.setStatus(
                                studentId: studentId,
                                classId: classId,
                                patternType: patternType,
                                status: .dismissed,
                                reason: .pedagogicalAgreement,
                                note: "Acuerdo de trabajo con el alumno"
                            )
                        } label: {
                            Label("Descartar: Acuerdo pedagógico", systemImage: "person.badge.shield.checkmark")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Resolver o descartar alerta")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            insight.priority.tint.opacity(0.04)
                .overlay(
                    RoundedRectangle(cornerRadius: EvaluationDesign.pillRadius, style: .continuous)
                        .stroke(insight.priority.tint.opacity(0.12), lineWidth: 1)
                )
        )
        .cornerRadius(EvaluationDesign.pillRadius)
    }
}
