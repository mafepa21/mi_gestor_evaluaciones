import SwiftUI
import MiGestorKit

// MARK: - Custom Scrollable Class Picker Popover Content
struct NotebookClassPickerPopover: View {
    let classes: [SchoolClass]
    let selectedClassId: Int64?
    let onSelectClass: (Int64) -> Void
    let onClose: () -> Void

    private var groupedNotebookClasses: [(course: Int32, classes: [SchoolClass])] {
        Dictionary(grouping: classes, by: \.course)
            .map { course, classes in
                (
                    course: course,
                    classes: classes.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                )
            }
            .sorted { $0.course < $1.course }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groupedNotebookClasses, id: \.course) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(group.course)º")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        ForEach(group.classes, id: \.id) { schoolClass in
                            Button {
                                onSelectClass(schoolClass.id)
                                onClose()
                            } label: {
                                HStack {
                                    Text(schoolClass.name)
                                        .font(.system(size: 14, weight: selectedClassId == schoolClass.id ? .semibold : .regular, design: .rounded))
                                        .foregroundStyle(selectedClassId == schoolClass.id ? Color.accentColor : .primary)
                                    Spacer()
                                    if selectedClassId == schoolClass.id {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(selectedClassId == schoolClass.id ? Color.accentColor.opacity(0.08) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if schoolClass.id != group.classes.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                                    .opacity(0.4)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 250)
        .frame(maxHeight: 350)
    }
}

// MARK: - Simple Scrollable Class List Popover (for TopBar and CompactCommandBar)
struct SimpleClassPickerPopover: View {
    let classes: [SchoolClass]
    let selectedClassId: Int64?
    let onSelectClass: (Int64) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(classes, id: \.id) { schoolClass in
                    Button {
                        onSelectClass(schoolClass.id)
                        onClose()
                    } label: {
                        HStack {
                            Text(schoolClass.name)
                                .font(.system(size: 14, weight: selectedClassId == schoolClass.id ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(selectedClassId == schoolClass.id ? Color.accentColor : .primary)
                            Spacer()
                            if selectedClassId == schoolClass.id {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(selectedClassId == schoolClass.id ? Color.accentColor.opacity(0.08) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if schoolClass.id != classes.last?.id {
                        Divider()
                            .padding(.leading, 16)
                            .opacity(0.4)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 230)
        .frame(maxHeight: 320)
    }
}
