import SwiftUI
import MiGestorKit

#if canImport(UIKit)
import UIKit
#endif

extension Student: @retroactive Identifiable {}

struct WeeklyStudentEmailWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let preselectedStudent: Student?
    let preselectedClassId: Int64?

    @State private var selectedClassId: Int64?
    @State private var audienceMode: WeeklyEmailAudienceMode = .student
    @State private var weekRangeDescription: String = "esta semana"
    
    @State private var students: [Student] = []
    @State private var draftsByStudentId: [Int64: WeeklyStudentEmailDraft] = [:]
    @State private var isGeneratingAll: Bool = false
    @State private var generatingStudentId: Int64? = nil
    @State private var activeDraftStudent: Student? = nil
    
    @State private var emailEditorStudent: Student? = nil
    @State private var tempEditingEmail: String = ""

    private let emailService = AppleFoundationStudentEmailService()

    init(student: Student? = nil, classId: Int64? = nil) {
        self.preselectedStudent = student
        self.preselectedClassId = classId
        _selectedClassId = State(initialValue: classId)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerControlsView
                
                if students.isEmpty {
                    emptyStateView
                } else {
                    mainContentView
                }
            }
            .background(Color.primary.opacity(0.03))
            .navigationTitle("Correos Semanales de Evaluación")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await generateAllDrafts() }
                    } label: {
                        Label("Generar Lote", systemImage: "sparkles")
                    }
                    .disabled(isGeneratingAll || students.isEmpty)
                }
            }
            .task {
                await loadData()
            }
            .sheet(item: $activeDraftStudent) { student in
                if let draft = draftsByStudentId[student.id] {
                    WeeklyDraftInspectorSheet(
                        student: student,
                        draft: draft,
                        onSave: { updatedDraft in
                            draftsByStudentId[student.id] = updatedDraft
                        }
                    )
                }
            }
            .sheet(item: $emailEditorStudent) { student in
                quickEmailEditorSheet(student: student)
            }
        }
    }

    // MARK: - Subviews

    private var headerControlsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Audience Picker
                Picker("Público", selection: $audienceMode) {
                    ForEach(WeeklyEmailAudienceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if bridge.classes.count > 1 {
                    Menu {
                        ForEach(bridge.classes, id: \.id) { cls in
                            Button(cls.name) {
                                selectedClassId = cls.id
                                Task { await loadStudentsForClass(cls.id) }
                            }
                        }
                    } label: {
                        HStack {
                            Text(currentClassName)
                                .font(.subheadline.bold())
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(EvaluationDesign.surface)
                        .cornerRadius(8)
                    }
                }
            }

            HStack(spacing: 16) {
                statBadge(title: "Alumnos", value: "\(students.count)", icon: "person.3.fill", color: .blue)
                statBadge(title: "Con Email", value: "\(studentsWithEmailCount)", icon: "envelope.checkmark.fill", color: .green)
                statBadge(title: "Borradores IA", value: "\(draftsByStudentId.count)", icon: "sparkles", color: .purple)
                
                Spacer()
                
                Button {
                    Task { await generateAllDrafts() }
                } label: {
                    HStack(spacing: 6) {
                        if isGeneratingAll {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(isGeneratingAll ? "Generando..." : "Generar con IA")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(EvaluationDesign.accent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isGeneratingAll || students.isEmpty)
            }
        }
        .padding(16)
        .background(EvaluationDesign.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(EvaluationDesign.border),
            alignment: .bottom
        )
    }

    private var mainContentView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(students, id: \.id) { student in
                    studentEmailCard(student)
                }
            }
            .padding(16)
        }
    }

    private func studentEmailCard(_ student: Student) -> some View {
        let hasEmail = student.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasDraft = draftsByStudentId[student.id] != nil
        let isGenerating = generatingStudentId == student.id

        return HStack(spacing: 14) {
            // Student Initials Avatar
            ZStack {
                Circle()
                    .fill(EvaluationDesign.accent.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(studentInitials(student))
                    .font(.headline.bold())
                    .foregroundColor(EvaluationDesign.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(student.firstName) \(student.lastName)")
                        .font(.body.bold())
                        .foregroundColor(.primary)
                    
                    if hasDraft {
                        let isAI = draftsByStudentId[student.id]?.isAIGenerated ?? false
                        AppleAIStatusBadge(
                            state: isAI ? .available : .rulesFallback,
                            message: isAI ? "Foundation Models" : "Reglas deterministas"
                        )
                    }
                }

                HStack(spacing: 6) {
                    if hasEmail {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(student.email ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Sin correo configurado")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        
                        Button("Añadir") {
                            tempEditingEmail = ""
                            emailEditorStudent = student
                        }
                        .font(.caption.bold())
                        .foregroundColor(EvaluationDesign.accent)
                    }
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else if hasDraft {
                    Button {
                        activeDraftStudent = student
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("Ver Borrador")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(EvaluationDesign.accent.opacity(0.12))
                        .foregroundColor(EvaluationDesign.accent)
                        .cornerRadius(6)
                    }
                } else {
                    Button {
                        Task { await generateDraftForStudent(student) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Redactar")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(EvaluationDesign.surfaceMuted)
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(12)
        .background(EvaluationDesign.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(hasDraft ? EvaluationDesign.accent.opacity(0.3) : EvaluationDesign.border, lineWidth: 1)
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.shield.halffilled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No se encontraron alumnos en este grupo")
                .font(.headline.bold())
                .foregroundColor(.primary)
            Text("Selecciona una clase o grupo para generar los borradores semanales de evaluación.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func statBadge(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Text(title)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(EvaluationDesign.surfaceMuted)
        .cornerRadius(6)
    }

    private func quickEmailEditorSheet(student: Student) -> some View {
        NavigationStack {
            Form {
                Section("Correo del alumno") {
                    Text("\(student.firstName) \(student.lastName)")
                        .font(.body.bold())
                    TextField("correo@ejemplo.com", text: $tempEditingEmail)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        #endif
                }
            }
            .navigationTitle("Añadir Correo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { emailEditorStudent = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task {
                            try? await bridge.updateMacStudent(
                                student: student,
                                firstName: student.firstName,
                                lastName: student.lastName,
                                email: tempEditingEmail,
                                isInjured: student.isInjured
                            )
                            emailEditorStudent = nil
                            await loadData()
                        }
                    }
                    .disabled(tempEditingEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Logic & Actions

    private var currentClassName: String {
        guard let selectedClassId else { return "Seleccionar Grupo" }
        return bridge.classes.first(where: { $0.id == selectedClassId })?.name ?? "Grupo"
    }

    private var studentsWithEmailCount: Int {
        students.filter { $0.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count
    }

    private func studentInitials(_ student: Student) -> String {
        let f = student.firstName.first.map(String.init) ?? ""
        let l = student.lastName.first.map(String.init) ?? ""
        return "\(f)\(l)".uppercased()
    }

    private func loadData() async {
        if let preselectedClassId {
            selectedClassId = preselectedClassId
            await loadStudentsForClass(preselectedClassId)
        } else if let firstClass = bridge.classes.first {
            selectedClassId = firstClass.id
            await loadStudentsForClass(firstClass.id)
        } else {
            self.students = bridge.allStudents
        }
        
        if let preselectedStudent {
            await generateDraftForStudent(preselectedStudent)
            activeDraftStudent = preselectedStudent
        }
    }

    private func loadStudentsForClass(_ classId: Int64) async {
        let inClass = bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass
        self.students = inClass
    }

    private func generateDraftForStudent(_ student: Student) async {
        generatingStudentId = student.id
        defer { generatingStudentId = nil }

        let evidence = StudentInsightEvidence(
            studentId: student.id,
            studentName: "\(student.firstName) \(student.lastName)",
            averageText: "Ver cuaderno",
            averageScore: nil,
            attendanceStatus: nil,
            followUpCount: 0,
            incidentCount: 0,
            evidenceCount: 0,
            competencyLabels: [],
            observations: [],
            rubricSummaries: [],
            averageExplanation: nil,
            trends: nil
        )

        let draft = await emailService.generateWeeklyEmailDraft(
            from: evidence,
            recipientEmail: student.email,
            audienceMode: audienceMode,
            weekRangeDescription: weekRangeDescription
        )
        draftsByStudentId[student.id] = draft
    }

    private func generateAllDrafts() async {
        isGeneratingAll = true
        defer { isGeneratingAll = false }

        for student in students {
            let evidence = StudentInsightEvidence(
                studentId: student.id,
                studentName: "\(student.firstName) \(student.lastName)",
                averageText: "Ver cuaderno",
                averageScore: nil,
                attendanceStatus: nil,
                followUpCount: 0,
                incidentCount: 0,
                evidenceCount: 0,
                competencyLabels: [],
                observations: [],
                rubricSummaries: [],
                averageExplanation: nil,
                trends: nil
            )

            let draft = await emailService.generateWeeklyEmailDraft(
                from: evidence,
                recipientEmail: student.email,
                audienceMode: audienceMode,
                weekRangeDescription: weekRangeDescription
            )
            draftsByStudentId[student.id] = draft
        }
    }
}

// MARK: - Draft Inspector Sheet

struct WeeklyDraftInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let student: Student
    @State var draft: WeeklyStudentEmailDraft
    let onSave: (WeeklyStudentEmailDraft) -> Void

    @State private var subjectText: String = ""
    @State private var bodyText: String = ""
    @State private var showCopiedAlert: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Status
                    HStack {
                        AppleAIStatusBadge(
                            state: draft.isAIGenerated ? .available : .rulesFallback,
                            message: draft.isAIGenerated ? "Foundation Models" : "Reglas deterministas"
                        )
                        Spacer()
                        Label(draft.audienceMode.title, systemImage: draft.audienceMode.iconName)
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }

                    // Email Header Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Destinatario")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(EvaluationDesign.accent)
                            Text(draft.recipientEmail ?? "Sin correo asignado")
                                .font(.body.bold())
                                .foregroundColor(draft.recipientEmail == nil ? .orange : .primary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(EvaluationDesign.surfaceMuted)
                        .cornerRadius(8)
                    }

                    // Subject Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Asunto")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("Asunto del correo", text: $subjectText)
                            .font(.body.bold())
                            .padding(10)
                            .background(EvaluationDesign.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(EvaluationDesign.border, lineWidth: 1)
                            )
                    }

                    // Body Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cuerpo del Correo (Borrador Formateado)")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextEditor(text: $bodyText)
                            .font(.body)
                            .frame(minHeight: 240)
                            .padding(8)
                            .background(EvaluationDesign.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(EvaluationDesign.border, lineWidth: 1)
                            )
                    }

                    // Primary Dispatcher Actions
                    HStack(spacing: 12) {
                        Button {
                            if let url = draft.mailtoURL {
                                openURL(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("Abrir en Mail")
                            }
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(draft.mailtoURL != nil ? EvaluationDesign.accent : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(draft.mailtoURL == nil)

                        Button {
                            copyToClipboard(bodyText)
                            showCopiedAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.doc.fill")
                                Text("Copiar")
                            }
                            .font(.body.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(EvaluationDesign.surfaceMuted)
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.primary.opacity(0.03))
            .navigationTitle("Borrador: \(student.firstName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let updated = WeeklyStudentEmailDraft(
                            id: draft.id,
                            studentId: draft.studentId,
                            studentName: draft.studentName,
                            recipientEmail: draft.recipientEmail,
                            audienceMode: draft.audienceMode,
                            weekRangeDescription: draft.weekRangeDescription,
                            subject: subjectText,
                            greeting: draft.greeting,
                            evaluativeSummary: draft.evaluativeSummary,
                            strengths: draft.strengths,
                            improvementAreas: draft.improvementAreas,
                            upcomingMilestones: draft.upcomingMilestones,
                            closing: draft.closing,
                            fullBodyText: bodyText,
                            isAIGenerated: draft.isAIGenerated
                        )
                        onSave(updated)
                        dismiss()
                    }
                }
            }
            .onAppear {
                subjectText = draft.subject
                bodyText = draft.fullBodyText
            }
            .alert("Copiado al portapapeles", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("El borrador del correo se ha copiado correctamente.")
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
