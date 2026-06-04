import SwiftUI

struct EvaluationSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    
    var body: some View {
        Form {
            Section("Criterios de Evaluación") {
                TextField("Escala por defecto", text: $settings.defaultGradeScale)
            }
            
            Section("Algoritmo de Cálculo") {
                Picker("Redondeo de medias", selection: $settings.averageRoundingMode) {
                    ForEach(AverageRoundingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
        }
        .navigationTitle("Evaluación")
    }
}
