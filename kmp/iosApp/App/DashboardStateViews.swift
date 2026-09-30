import SwiftUI

// MARK: - Estados del Dashboard: cargando, error de red, sync en curso
//
// Reglas de la maqueta:
// - El esqueleto tiene la forma real de cada bloque y NO usa `LazyVGrid`
//   flexible (pide ancho infinito y ya cerró la app una vez): solo pilas y
//   filas con tamaños fijos.
// - Durante una recarga se mantiene el contenido anterior; el esqueleto solo
//   sale la primera vez, cuando no hay nada que enseñar.
// - Error de red: banner con Reintentar y contenido anterior atenuado (>= 75 %).

// MARK: Esqueleto de Despacho

struct DashboardDispatchSkeleton: View {
    let singleColumn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s4) {
            nowSkeleton
            attentionSkeleton
            contextSkeleton
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando")
    }

    private var nowSkeleton: some View {
        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s2) {
            DashboardSkeletonShape(width: 80, height: 12)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s1) {
                    DashboardSkeletonShape(width: 192, height: 34)
                    DashboardSkeletonShape(width: 256, height: 16)
                }
                Spacer(minLength: DashboardStyle.Spacing.s2)
                DashboardSkeletonShape(width: 96, height: 48)
            }
            DashboardSkeletonShape(height: 8, capsule: true)
            HStack(spacing: DashboardStyle.Spacing.s2) {
                DashboardSkeletonShape(width: 168, height: 56, radius: DashboardStyle.Radius.largeControl)
                DashboardSkeletonShape(width: 104, height: 56, radius: DashboardStyle.Radius.largeControl)
            }
        }
        .dashboardCard()
    }

    private var attentionSkeleton: some View {
        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s2) {
            DashboardSkeletonShape(width: 256, height: 16)
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: DashboardStyle.Spacing.s2) {
                    DashboardSkeletonShape(width: 40, height: 40, radius: 12)
                    VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s1) {
                        DashboardSkeletonShape(width: 224, height: 16)
                        DashboardSkeletonShape(width: 144, height: 14)
                    }
                    Spacer(minLength: DashboardStyle.Spacing.s2)
                    DashboardSkeletonShape(width: 80, height: 44, capsule: true)
                }
                .frame(minHeight: 72)
            }
        }
        .dashboardCard()
    }

    private var contextSkeleton: some View {
        let layout = singleColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DashboardStyle.Spacing.s2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DashboardStyle.Spacing.s2))
        return layout {
            ForEach(0..<3, id: \.self) { _ in
                DashboardSkeletonShape(width: 160, height: 16)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .dashboardCard(padding: DashboardStyle.Spacing.s3)
            }
        }
    }
}

// MARK: Esqueleto de Clase

struct DashboardClassroomSkeleton: View {
    let singleColumn: Bool

    var body: some View {
        VStack(spacing: DashboardStyle.Spacing.s4) {
            DashboardSkeletonShape(width: 240, height: 96)
            DashboardSkeletonShape(width: 224, height: 34)
            DashboardSkeletonShape(width: 448, height: 8, capsule: true)
                .frame(maxWidth: 448)
            let layout = singleColumn
                ? AnyLayout(VStackLayout(spacing: DashboardStyle.Spacing.s2))
                : AnyLayout(HStackLayout(spacing: DashboardStyle.Spacing.s2))
            layout {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s1) {
                        DashboardSkeletonShape(width: 96, height: 12)
                        DashboardSkeletonShape(width: 64, height: 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dashboardCard(padding: DashboardStyle.Spacing.s2)
                }
            }
            HStack(spacing: DashboardStyle.Spacing.s2) {
                DashboardSkeletonShape(width: 160, height: 56, radius: DashboardStyle.Radius.largeControl)
                DashboardSkeletonShape(width: 144, height: 56, radius: DashboardStyle.Radius.largeControl)
            }
        }
        .frame(maxWidth: 704)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando")
    }
}

// MARK: Sync en curso

/// Línea fina bajo la cabecera mientras hay una recarga o sincronización.
/// Con movimiento reducido no se desplaza: queda fija.
struct DashboardSyncLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moving = false

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, DashboardStyle.accent, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geometry.size.width * 0.4, height: 3)
                .offset(x: reduceMotion ? geometry.size.width * 0.3 : (moving ? geometry.size.width : -geometry.size.width * 0.4))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        moving = true
                    }
                }
        }
        .frame(height: 3)
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: Error de red

/// Aviso de cristal: contenido anterior visible, hora de la última carga y
/// Reintentar. Se anuncia como alerta a VoiceOver.
struct DashboardErrorBanner: View {
    let lastLoadedAt: Date?
    let isRetrying: Bool
    let onRetry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var timeText: String? {
        lastLoadedAt.map { "Datos de las \($0.formatted(date: .omitted, time: .shortened))." }
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DashboardStyle.Spacing.s1))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DashboardStyle.Spacing.s2))
        layout {
            Image(systemName: "wifi.slash")
                .font(.headline)
                .foregroundStyle(DashboardStyle.Tint.alert)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Sin conexión.").font(DashboardStyle.Typography.subheadline.weight(.semibold))
                if let timeText {
                    Text(timeText)
                        .font(DashboardStyle.Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRetry) {
                Text("Reintentar")
                    .font(DashboardStyle.Typography.footnoteStrong)
            }
            .dashboardButtonStyle()
            .disabled(isRetrying)
        }
        .padding(.horizontal, DashboardStyle.Spacing.s2)
        .padding(.vertical, DashboardStyle.Spacing.s1)
        .dashboardGlass(in: DashboardStyle.controlShape())
        .overlay(DashboardStyle.controlShape().fill(DashboardStyle.Tint.alert.opacity(0.10)).allowsHitTesting(false))
        .overlay(DashboardStyle.controlShape().strokeBorder(DashboardStyle.Tint.alert.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Sin datos previos y la carga ha fallado: no hay nada que atenuar, así que
/// se enseña el fallo con su salida.
struct DashboardLoadFailureView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: DashboardStyle.Spacing.s2) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(DashboardStyle.Tint.alert)
                .accessibilityHidden(true)
            Text("No se pudo cargar el Dashboard")
                .font(DashboardStyle.Typography.headline)
            Text("Comprueba la conexión e inténtalo de nuevo.")
                .font(DashboardStyle.Typography.subheadline)
                .foregroundStyle(.secondary)
            Button("Reintentar", action: onRetry)
                .dashboardButtonStyle(prominent: true, large: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DashboardStyle.Spacing.s5)
        .dashboardCard()
        .accessibilityElement(children: .contain)
    }
}

// MARK: Sin clases

/// Con cero clases todos los bloques dirían "sin datos": un único estado con
/// una salida clara. Lo usan iPad y Mac; cada uno resuelve el destino.
struct DashboardNoClassesView: View {
    let singleColumn: Bool
    let onOpen: (AppWorkspaceModule) -> Void

    var body: some View {
        let layout = singleColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DashboardStyle.Spacing.s1))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DashboardStyle.Spacing.s1))
        return VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s3) {
            HStack(alignment: .top, spacing: DashboardStyle.Spacing.s2) {
                Image(systemName: "person.3.sequence")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DashboardStyle.accent)
                    .frame(width: 56, height: 56)
                    .background(DashboardStyle.accent.opacity(0.12), in: DashboardStyle.controlShape())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s1) {
                    Text("Sin clases todavía")
                        .font(DashboardStyle.Typography.title)
                    Text("Crea tu primera clase para empezar a ver aquí las sesiones, alertas y evaluaciones del día.")
                        .font(DashboardStyle.Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Sin clases, la salida buena es el recorrido guiado:
            // fechas → horario → grupos → alumnado.
            Button("Configurar mi curso") {
                OnboardingStore.shared.openChecklist()
            }
            .dashboardButtonStyle(prominent: true, large: true)

            layout {
                actionCard("Crear grupo", "Empieza por el alumnado y sus clases.", "person.3.sequence", .courses)
                actionCard("Planificar semana", "Define sesiones aunque no haya grupo aún.", "calendar.badge.plus", .planner)
                actionCard("Importar situación", "Sube un documento LOMLOE para programarlo después.", "doc.text.magnifyingglass", .situations)
            }
        }
        .dashboardCard()
    }

    private func actionCard(_ title: String, _ subtitle: String, _ systemImage: String, _ module: AppWorkspaceModule) -> some View {
        Button { onOpen(module) } label: {
            HStack(alignment: .top, spacing: DashboardStyle.Spacing.s1) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(DashboardStyle.accent)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DashboardStyle.Spacing.micro) {
                    Text(title)
                        .font(DashboardStyle.Typography.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(DashboardStyle.Typography.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(DashboardStyle.Spacing.s2)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(DashboardStyle.insetFill, in: DashboardStyle.controlShape())
            .contentShape(DashboardStyle.controlShape())
        }
        .buttonStyle(.plain)
        .dashboardRowHover()
    }
}
