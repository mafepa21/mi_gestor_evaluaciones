import SwiftUI
import SwiftData

/// Módulo «Libreta» de Mi Gestor: la estantería de Cuadernos dentro del panel de detalle.
/// El lector se abre a pantalla completa desde `LibraryView`.
struct LibretaModuleView: View {
    @ObservedObject private var store = LibretaStore.shared

    var body: some View {
        Group {
            switch store.state {
            case .ready(let container):
                LibraryView()
                    .modelContainer(container)
            case .loading:
                ProgressView("Cargando libretas…")
                    .tint(Theme.inkSecondary)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ShelfBackground().ignoresSafeArea())
                    .navigationTitle("Libreta")
            case .failed:
                LibretaErrorView(onRetry: store.retry)
                    .navigationTitle("Libreta")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { store.loadIfNeeded() }
    }
}

/// Estado vacío: una sola acción principal y la vía para traer lo que había en Cuadernos.
struct LibretaEmptyView: View {
    let onNew: () -> Void
    let onImport: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NotebookCoverView(title: "Primera libreta", color: .blue,
                                  size: CGSize(width: 112, height: 112 / Theme.coverAspect))
                    .accessibilityHidden(true)
                    .padding(.bottom, 8)
                Text("Aún no tienes libretas")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Crea una para tomar notas a mano. Si ya usabas Cuadernos, trae tus libretas con su copia.")
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }
                    VStack(spacing: 8) { buttons }
                }
                .padding(.top, 8)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        }
        .background(ShelfBackground().ignoresSafeArea())
    }

    @ViewBuilder private var buttons: some View {
        Button(action: onNew) {
            Label("Nueva libreta", systemImage: "plus")
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        Button(action: onImport) {
            Label("Traer de Cuadernos", systemImage: "square.and.arrow.down")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
    }
}

/// Error al abrir la base: se dice una vez, arriba, con una acción. Nada se borra.
struct LibretaErrorView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No se pudieron abrir tus libretas.")
                        .font(.headline)
                    Text("Siguen guardadas en este iPad. Prueba otra vez.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Reintentar", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            .accessibilityElement(children: .contain)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShelfBackground().ignoresSafeArea())
    }
}
