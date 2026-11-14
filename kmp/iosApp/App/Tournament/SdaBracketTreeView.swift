import SwiftUI

/// Cuadro dibujado como un solo árbol horizontal: una columna por ronda, una tarjeta por partido,
/// líneas continuas cuando gana (sube) y discontinuas cuando pierde (baja), bandas con los puestos
/// en juego y una columna final con el puesto de cada pareja. «Seguir a» ilumina el camino de una
/// pareja. La lógica vive en `BracketTreeLayout`; aquí solo se dibuja.
struct SdaBracketTreeView: View {
    let layout: BracketTreeLayout
    /// Si se puede abrir el marcador del partido (ya hay dos parejas y la fase está abierta).
    let canScore: (UUID) -> Bool
    let onSelectMatch: (UUID) -> Void

    @State private var followedTeamID: String?
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 192
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 34

    private let stripWidth: CGFloat = 24
    private let columnGap: CGFloat = 48
    private let headerHeight: CGFloat = 56
    private let rowGap: CGFloat = 12
    private let leafWidth: CGFloat = 156
    private let leafHeight: CGFloat = 36
    private let maximumVisibleHeight: CGFloat = 640

    private var cardHeight: CGFloat { rowHeight * 2 + 2 }
    private var pitch: CGFloat { cardHeight + rowGap }
    private var stripSpace: CGFloat { layout.isPlacement ? stripWidth : 0 }
    private var columnWidth: CGFloat { stripSpace + cardWidth }

    private var path: BracketTeamPath? { followedTeamID.flatMap { layout.path(for: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            followBar
            if let path {
                Text(path.summaryText)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(EvaluationDesign.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
                    .accessibilityLabel("Camino de \(path.teamName). \(path.summaryText)")
            }
            tree
            legend
        }
    }

    // MARK: Seguir a

    private var followBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    followedTeamID = nil
                } label: {
                    if followedTeamID == nil {
                        Label("Nadie", systemImage: "checkmark")
                    } else {
                        Text("Nadie")
                    }
                }
                Divider()
                ForEach(layout.followableTeams, id: \.id) { team in
                    Button {
                        followedTeamID = team.id
                    } label: {
                        if followedTeamID == team.id {
                            Label(team.name, systemImage: "checkmark")
                        } else {
                            Text(team.name)
                        }
                    }
                }
            } label: {
                Label(
                    "Seguir a: \(path?.teamName ?? "nadie")",
                    systemImage: followedTeamID == nil ? "scope" : "scope.fill"
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .accessibilityLabel("Seguir a una pareja")
            .accessibilityValue(path?.teamName ?? "nadie")
            .accessibilityHint("Ilumina su camino por el cuadro.")
            if followedTeamID != nil {
                Button {
                    followedTeamID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dejar de seguir")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Árbol

    private var tree: some View {
        let geometry = Geometry(layout: layout, metrics: metrics)
        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                edgesCanvas(geometry)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(true)
                ForEach(layout.columns) { column in
                    columnHeader(column, geometry: geometry)
                }
                finalColumnHeader(geometry)
                if layout.isPlacement {
                    ForEach(geometry.bands) { band in
                        bandStrip(band)
                    }
                }
                ForEach(layout.nodes) { node in
                    if let origin = geometry.nodeOrigin[node.id] {
                        card(node)
                            .frame(width: cardWidth, height: cardHeight)
                            .offset(x: origin.x, y: origin.y)
                    }
                }
                ForEach(layout.leaves) { leaf in
                    if let origin = geometry.leafOrigin[leaf.id] {
                        leafView(leaf)
                            .frame(width: leafWidth, height: leafHeight)
                            .offset(x: origin.x, y: origin.y)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: min(geometry.size.height + 8, maximumVisibleHeight))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cuadro del torneo")
    }

    private var metrics: Geometry.Metrics {
        Geometry.Metrics(
            stripSpace: stripSpace, cardWidth: cardWidth, cardHeight: cardHeight, columnGap: columnGap,
            headerHeight: headerHeight, pitch: pitch, leafWidth: leafWidth, leafHeight: leafHeight
        )
    }

    private func edgesCanvas(_ geometry: Geometry) -> some View {
        let selecting = path != nil
        let highlighted = path?.highlightedEdgeIDs ?? []
        let ordered = layout.edges.sorted { !highlighted.contains($0.id) && highlighted.contains($1.id) }
        return Canvas { context, _ in
            for edge in ordered {
                guard let from = geometry.start(of: edge), let to = geometry.end(of: edge) else { continue }
                let isOn = highlighted.contains(edge.id)
                var line = Path()
                line.move(to: from)
                let midX = (from.x + to.x) / 2
                line.addCurve(
                    to: to,
                    control1: CGPoint(x: midX, y: from.y),
                    control2: CGPoint(x: midX, y: to.y)
                )
                let color: Color = isOn ? EvaluationDesign.accent : Color.secondary.opacity(selecting ? 0.18 : 0.55)
                let style = StrokeStyle(
                    lineWidth: isOn ? 3 : 1.5,
                    lineCap: .round,
                    dash: edge.kind == .loser ? [6, 5] : []
                )
                context.stroke(line, with: .color(color), style: style)
            }
        }
    }

    private func columnHeader(_ column: BracketColumn, geometry: Geometry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(column.headerText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(column.state == .current ? EvaluationDesign.accent : Color.primary)
            if let subtitle = column.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(2)
        .frame(width: cardWidth, height: headerHeight - 8, alignment: .topLeading)
        .offset(x: geometry.columnX(column.id) + stripSpace, y: 0)
        .accessibilityAddTraits(.isHeader)
    }

    private func finalColumnHeader(_ geometry: Geometry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(layout.finalColumnTitle)
                .font(.subheadline.weight(.semibold))
            if let subtitle = layout.finalColumnSubtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: leafWidth, height: headerHeight - 8, alignment: .topLeading)
        .offset(x: geometry.finalX, y: 0)
        .accessibilityAddTraits(.isHeader)
    }

    private func bandStrip(_ band: Geometry.Band) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(IOSAppStyle.subtleFill)
            .frame(width: stripWidth - 4, height: band.height)
            .overlay {
                Text("Puestos \(BracketTreeLayout.positionsText(band.positions))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            }
            .clipped()
            .offset(x: band.x, y: band.y)
            .accessibilityHidden(true)
    }

    // MARK: Tarjeta de partido

    private func card(_ node: BracketNode) -> some View {
        let enabled = canScore(node.id)
        let dimmed = path != nil && !(path?.highlightedNodeIDs.contains(node.id) ?? false)
        let onPath = path?.highlightedNodeIDs.contains(node.id) ?? false
        return Button {
            onSelectMatch(node.id)
        } label: {
            VStack(spacing: 0) {
                sideRow(node.home, node: node)
                Divider()
                sideRow(node.away, node: node)
            }
            .background(
                onPath ? EvaluationDesign.accent.opacity(0.10) : IOSAppStyle.cardBackground,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay { border(for: node, onPath: onPath) }
            .overlay(alignment: .topLeading) {
                Text("P\(node.number)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(IOSAppStyle.cardBackground, in: Capsule())
                    .offset(x: 6, y: -8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(dimmed ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(for: node))
        .accessibilityHint(enabled ? "Toca para registrar o cambiar el resultado." : "Aún no se conocen las dos parejas.")
    }

    @ViewBuilder
    private func border(for node: BracketNode, onPath: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        switch node.status {
        case .inPlay:
            shape.stroke(IOSAppStyle.warning, lineWidth: 2)
        case .pending:
            shape.stroke(
                onPath ? EvaluationDesign.accent : Color.secondary.opacity(0.5),
                style: StrokeStyle(lineWidth: onPath ? 2 : 1, dash: [4, 3])
            )
        case .played:
            shape.stroke(onPath ? EvaluationDesign.accent : IOSAppStyle.cardBorder, lineWidth: onPath ? 2 : 1)
        }
    }

    private func sideRow(_ side: BracketSide, node: BracketNode) -> some View {
        let isFollowed = side.teamID != nil && side.teamID == followedTeamID
        return HStack(spacing: 6) {
            Text(side.label)
                .font(.callout)
                .fontWeight(side.isWinner || isFollowed ? .bold : .regular)
                .foregroundStyle(side.isResolved ? Color.primary : Color.secondary)
                .italic(!side.isResolved)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if side.isDirectPass {
                Image(systemName: "arrow.up.forward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let score = side.score {
                Text("\(score)")
                    .font(.callout.weight(side.isWinner ? .bold : .regular).monospacedDigit())
            }
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
    }

    private func accessibilityText(for node: BracketNode) -> String {
        var text = "Partido \(node.number), ronda \(node.round)"
        if let positions = node.positions {
            text += ", puestos \(positions.lowerBound) a \(positions.upperBound)"
        }
        text += ". \(node.home.label) contra \(node.away.label)."
        switch node.status {
        case .played:
            if let home = node.home.score, let away = node.away.score {
                let winner = node.winnerTeamName.map { " Gana \($0)." } ?? ""
                text += " Resultado: \(home) a \(away).\(winner)"
            }
        case .inPlay:
            text += " En juego en la pista \(node.venue)."
        case .pending:
            text += " Pendiente."
        }
        text += " \(node.destinationText)."
        return text
    }

    // MARK: Puesto final

    private func leafView(_ leaf: BracketLeaf) -> some View {
        let onPath = path?.highlightedLeafIDs.contains(leaf.id) ?? false
        let dimmed = path != nil && !onPath
        let isTop = leaf.positions.lowerBound <= 3
        return HStack(spacing: 8) {
            Text(BracketTreeLayout.positionsText(leaf.positions))
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(isTop ? EvaluationDesign.accent : Color.secondary)
            Text(leaf.teamNames.joined(separator: ", "))
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .background(
            onPath ? EvaluationDesign.accent.opacity(0.12) : IOSAppStyle.subtleFill,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .opacity(dimmed ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            leaf.teamNames.isEmpty
                ? "Puesto \(BracketTreeLayout.positionsText(leaf.positions)), aún sin decidir."
                : "Puesto \(BracketTreeLayout.positionsText(leaf.positions)): \(leaf.teamNames.joined(separator: ", "))."
        )
    }

    // MARK: Leyenda

    private var legend: some View {
        LearningSituationFlowLayout(spacing: 16) {
            legendItem("Gana y sube") { legendLine(dashed: false) }
            legendItem("Pierde y baja") { legendLine(dashed: true) }
            legendItem("En juego") {
                RoundedRectangle(cornerRadius: 3).stroke(IOSAppStyle.warning, lineWidth: 2).frame(width: 18, height: 12)
            }
            legendItem("Pendiente") {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 18, height: 12)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Leyenda. Línea continua: gana y sube. Línea discontinua: pierde y baja. Borde naranja: en juego. Borde discontinuo: pendiente.")
    }

    private func legendItem<Symbol: View>(_ title: String, @ViewBuilder symbol: () -> Symbol) -> some View {
        HStack(spacing: 6) {
            symbol()
            Text(title)
        }
    }

    private func legendLine(dashed: Bool) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 6))
            path.addLine(to: CGPoint(x: 22, y: 6))
        }
        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: dashed ? [4, 3] : []))
        .frame(width: 22, height: 12)
    }
}

// MARK: - Geometría

/// Posición de cada pieza del árbol. Valor puro para que el dibujo y las líneas coincidan.
private struct Geometry {
    struct Metrics {
        var stripSpace: CGFloat
        var cardWidth: CGFloat
        var cardHeight: CGFloat
        var columnGap: CGFloat
        var headerHeight: CGFloat
        var pitch: CGFloat
        var leafWidth: CGFloat
        var leafHeight: CGFloat
    }

    struct Band: Identifiable {
        var id: String
        var positions: ClosedRange<Int>
        var x: CGFloat
        var y: CGFloat
        var height: CGFloat
    }

    let metrics: Metrics
    let columnCount: Int
    var nodeOrigin: [UUID: CGPoint] = [:]
    var leafOrigin: [Int: CGPoint] = [:]
    var bands: [Band] = []
    var size: CGSize = .zero

    init(layout: BracketTreeLayout, metrics: Metrics) {
        self.metrics = metrics
        columnCount = layout.columns.count

        var bottom: CGFloat = metrics.headerHeight
        for node in layout.nodes {
            let origin = CGPoint(
                x: columnX(node.column) + metrics.stripSpace,
                y: metrics.headerHeight + CGFloat(node.yRow) * metrics.pitch
            )
            nodeOrigin[node.id] = origin
            bottom = max(bottom, origin.y + metrics.cardHeight)
        }

        // Bandas de puestos: un rectángulo por columna y grupo de puestos.
        var grouped: [String: (positions: ClosedRange<Int>, column: Int, top: CGFloat, bottom: CGFloat)] = [:]
        for node in layout.nodes {
            guard let positions = node.positions, let origin = nodeOrigin[node.id] else { continue }
            let key = "\(node.column)-\(positions.lowerBound)-\(positions.upperBound)"
            let top = min(grouped[key]?.top ?? .infinity, origin.y)
            let low = max(grouped[key]?.bottom ?? 0, origin.y + metrics.cardHeight)
            grouped[key] = (positions, node.column, top, low)
        }
        bands = grouped.map { key, value in
            Band(id: key, positions: value.positions, x: columnX(value.column), y: value.top, height: value.bottom - value.top)
        }.sorted { $0.id < $1.id }

        // Puestos finales: a la altura de su partido de origen; si chocan, se separan hacia abajo.
        var wanted: [(id: Int, y: CGFloat)] = []
        for leaf in layout.leaves {
            let ys = leaf.sources.compactMap { source -> CGFloat? in
                guard let origin = nodeOrigin[source.nodeID] else { return nil }
                return origin.y + metrics.cardHeight * (source.kind == .winner ? 0.25 : 0.75) - metrics.leafHeight / 2
            }
            let y = ys.isEmpty ? bottom : ys.reduce(0, +) / CGFloat(ys.count)
            wanted.append((leaf.id, y))
        }
        var lastBottom = metrics.headerHeight - metrics.leafHeight
        for item in wanted.sorted(by: { ($0.y, $0.id) < ($1.y, $1.id) }) {
            let y = max(item.y, lastBottom + metrics.leafHeight + 4)
            leafOrigin[item.id] = CGPoint(x: finalXValue, y: y)
            lastBottom = y
            bottom = max(bottom, y + metrics.leafHeight)
        }
        size = CGSize(width: finalXValue + metrics.leafWidth + 8, height: bottom + 8)
    }

    func columnX(_ column: Int) -> CGFloat {
        CGFloat(column) * (metrics.stripSpace + metrics.cardWidth + metrics.columnGap)
    }

    private var finalXValue: CGFloat { columnX(columnCount) }
    var finalX: CGFloat { finalXValue }

    /// Salida de la línea: borde derecho del partido de origen.
    func start(of edge: BracketEdge) -> CGPoint? {
        guard let origin = nodeOrigin[edge.from] else { return nil }
        return CGPoint(x: origin.x + metrics.cardWidth, y: origin.y + metrics.cardHeight / 2)
    }

    /// Llegada de la línea: lado izquierdo de la fila (local o visitante) o del puesto final.
    func end(of edge: BracketEdge) -> CGPoint? {
        switch edge.target {
        case .node(let id, let side):
            guard let origin = nodeOrigin[id] else { return nil }
            return CGPoint(x: origin.x, y: origin.y + metrics.cardHeight * (side == .home ? 0.25 : 0.75))
        case .leaf(let id):
            guard let origin = leafOrigin[id] else { return nil }
            return CGPoint(x: origin.x, y: origin.y + metrics.leafHeight / 2)
        }
    }
}
