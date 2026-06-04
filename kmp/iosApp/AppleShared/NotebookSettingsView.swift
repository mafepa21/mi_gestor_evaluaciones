import SwiftUI

struct NotebookSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    
    var body: some View {
        Form {
            Section("Visualización del Cuaderno") {
                Picker("Densidad visual", selection: $settings.notebookDensity) {
                    ForEach(NotebookDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                
                Toggle("Ver valores físicos brutos", isOn: $settings.showRawPhysicalValues)
                Toggle("Ver explicación de medias", isOn: $settings.showAverageExplanation)
            }
        }
        .navigationTitle("Cuaderno")
    }
}
