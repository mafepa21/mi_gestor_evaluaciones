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

            TeacherProfileSettingsView(settings: settings)
        }
        .navigationTitle("General")
    }
}

struct TeacherProfileSettingsView: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        Section {
            ForEach(TeacherSubjectProfile.allCases) { profile in
                Toggle(isOn: binding(for: profile)) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.title)
                                .font(.headline)
                            Text(profile.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: profile.systemImage)
                    }
                }
            }
        } header: {
            Text("Perfil docente")
        } footer: {
            Text("El perfil general mantiene visible el core docente. Educación Física activa los módulos específicos de sesiones, mediciones, recursos, incidencias y torneos.")
        }
    }

    private func binding(for profile: TeacherSubjectProfile) -> Binding<Bool> {
        Binding(
            get: { settings.enabledSubjectProfiles.contains(profile) },
            set: { isEnabled in
                var next = settings.enabledSubjectProfiles
                if isEnabled {
                    next.insert(profile)
                } else {
                    next.remove(profile)
                }
                settings.enabledSubjectProfiles = next.isEmpty ? [.general] : next
            }
        )
    }
}
