import SwiftUI
import MiGestorKit

/// Hoja «Copiar a…» del menú contextual de la Semana: elegir grupo, día (de
/// cualquier semana) y franja. La franja se propone con el horario del grupo
/// ese día; si ese día no tiene clase, se puede elegir cualquier franja.
/// El destino ocupado lo confirma el coordinador, como en ⌘ + arrastrar.
struct PlannerCopySessionSheet: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession
    let onCopy: (_ groupId: Int64, _ date: Date, _ period: Int) -> Void
    let onCancel: () -> Void

    @State private var groupId: Int64
    @State private var date: Date
    @State private var period: Int?

    init(
        vm: PlannerWorkspaceViewModel,
        session: PlanningSession,
        onCopy: @escaping (_ groupId: Int64, _ date: Date, _ period: Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.vm = vm
        self.session = session
        self.onCopy = onCopy
        self.onCancel = onCancel
        _groupId = State(initialValue: session.groupId)
        _date = State(initialValue: vm.calendarDate(of: session) ?? .now)
        _period = State(initialValue: Int(session.period))
    }

    private var weekday: Int {
        // Calendar: 1 = domingo. Planner: 1 = lunes.
        let value = Calendar(identifier: .gregorian).component(.weekday, from: date)
        return (value + 5) % 7 + 1
    }

    private var groupSlots: [PlannerVisibleSlot] {
        vm.copyCandidateSlots(groupId: groupId, weekday: weekday)
    }

    private var slotChoices: [PlannerVisibleSlot] {
        groupSlots.isEmpty ? vm.visibleSlots : groupSlots
    }

    private var sourceSummary: String {
        let title = session.teachingUnitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateText = vm.calendarDate(of: session).map { Self.dateFormatter.string(from: $0) } ?? ""
        return [vm.groupLabel(for: session), dateText, title]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Copiar sesión")
                    .font(.title3.weight(.bold))
                Text(sourceSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Form {
                Picker("Grupo", selection: $groupId) {
                    ForEach(vm.groups, id: \.id) { group in
                        Text(vm.groupLabel(for: group)).tag(group.id)
                    }
                }
                DatePicker("Día", selection: $date, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "es_ES"))
                Section {
                    Picker("Franja", selection: $period) {
                        ForEach(slotChoices, id: \.period) { slot in
                            Text("\(slot.startTime)–\(slot.endTime)").tag(Optional(slot.period))
                        }
                    }
                } footer: {
                    if groupSlots.isEmpty {
                        Text("Ese grupo no tiene clase ese día en el horario. Elige la franja a mano.")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Copiar") {
                    guard let period else { return }
                    onCopy(groupId, date, period)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(period == nil)
            }
            .padding(20)
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 360)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .appOnChange(of: groupId) { _ in syncPeriod() }
        .appOnChange(of: date) { _ in syncPeriod() }
    }

    /// Al cambiar grupo o día, propone la primera franja de ese grupo ese día
    /// (o conserva la elegida si sigue valiendo).
    private func syncPeriod() {
        if let period, slotChoices.contains(where: { $0.period == period }), groupSlots.isEmpty || groupSlots.contains(where: { $0.period == period }) {
            return
        }
        period = slotChoices.first?.period
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEE d/M"
        return formatter
    }()
}
