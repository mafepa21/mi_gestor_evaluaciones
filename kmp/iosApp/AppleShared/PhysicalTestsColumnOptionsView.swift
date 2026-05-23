import SwiftUI

struct PhysicalTestsColumnOptionsView: View {
    @Binding var columnMode: PhysicalNotebookColumnMode
    @Binding var scoreCountsTowardAverage: Bool
    
    init(
        columnMode: Binding<PhysicalNotebookColumnMode>,
        scoreCountsTowardAverage: Binding<Bool>
    ) {
        self._columnMode = columnMode
        self._scoreCountsTowardAverage = scoreCountsTowardAverage
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 6) {
                Text("Columnas en cuaderno")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("", selection: $columnMode) {
                    ForEach(PhysicalNotebookColumnMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            #else
            VStack(alignment: .leading, spacing: 6) {
                Text("Columnas en cuaderno")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Columnas en cuaderno", selection: $columnMode) {
                    ForEach(PhysicalNotebookColumnMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            #endif
            
            if columnMode == .rawAndScore || columnMode == .scoreOnly {
                Toggle("La nota cuenta para la media", isOn: $scoreCountsTowardAverage)
                    .font(.body)
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
            }
            
            Text("Las notas se podrán ponderar después desde la columna Media.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
