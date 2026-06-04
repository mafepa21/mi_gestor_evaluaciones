import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    
    var body: some View {
        Form {
            Section("Tema de Color") {
                Picker("Apariencia", selection: $settings.themeModeRawValue) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                #if os(macOS)
                .pickerStyle(.inline)
                #else
                .pickerStyle(.segmented)
                #endif
            }
            
            Section("Ajustes del Sistema") {
                Toggle("Reducir movimiento", isOn: $settings.reduceMotion)
                Toggle("Densidad de tablas compacta", isOn: $settings.compactDensity)
            }
        }
        .navigationTitle("Apariencia")
    }
}
