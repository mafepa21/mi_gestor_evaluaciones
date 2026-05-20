import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    
    var body: some View {
        Form {
            Section("Curso Escolar") {
                TextField("Curso Académico", text: $settings.academicYear)
                TextField("Nombre del Centro", text: $settings.centerName)
            }
            
            Section("Identificación de Dispositivo") {
                TextField("Nombre del Dispositivo", text: $settings.deviceDisplayName)
            }
        }
        .navigationTitle("General")
    }
}
