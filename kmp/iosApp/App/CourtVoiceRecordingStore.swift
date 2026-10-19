import Foundation

// MARK: - Grabaciones de Voz de Pista (solo en el dispositivo)

/// Dictado guardado para analizarlo más tarde. El audio contiene voces y nombres del alumnado:
/// vive solo en este dispositivo, protegido, fuera de la copia de iCloud, y se borra al aplicar sus acciones.
struct CourtVoiceRecording: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let classId: Int64
    let createdAt: Date
    var duration: TimeInterval
    let instrumentColumnId: String?
    let title: String
    /// Se guarda al transcribir para no repetir el trabajo si se vuelve a analizar.
    var transcript: String?
    let fileName: String
}

struct CourtVoiceRecordingStore {
    let root: URL

    static let shared = CourtVoiceRecordingStore(
        root: (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("CourtVoiceRecordings", isDirectory: true)
    )

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    // MARK: Lectura

    func list(classId: Int64) -> [CourtVoiceRecording] {
        loadIndex()
            .filter { $0.classId == classId && FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fileURL(for recording: CourtVoiceRecording) -> URL {
        root.appendingPathComponent(String(recording.classId), isDirectory: true).appendingPathComponent(recording.fileName)
    }

    // MARK: Escritura

    /// Ruta para una grabación nueva. El archivo lo escribe el reconocedor mientras se dicta.
    func prepareNewFile(classId: Int64) throws -> (id: String, url: URL) {
        let id = UUID().uuidString
        let directory = root.appendingPathComponent(String(classId), isDirectory: true)
        try ensureDirectory(directory)
        return (id, directory.appendingPathComponent("\(id).m4a"))
    }

    /// Registra la grabación ya escrita. Título: «Instrumento · n» por día, o «Dictado · n».
    @discardableResult
    func register(
        id: String,
        classId: Int64,
        createdAt: Date,
        duration: TimeInterval,
        instrumentColumnId: String?,
        instrumentTitle: String?,
        transcript: String?
    ) -> CourtVoiceRecording {
        var index = loadIndex()
        let base = instrumentTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyRecording ?? "Dictado"
        // Siguiente número del día (aunque se haya borrado alguna, no se repiten títulos).
        let sameDay = index
            .filter { $0.classId == classId && Calendar.current.isDate($0.createdAt, inSameDayAs: createdAt) && $0.title.hasPrefix(base + " · ") }
            .compactMap { Int($0.title.dropFirst(base.count + 3)) }
            .max() ?? 0
        let recording = CourtVoiceRecording(
            id: id,
            classId: classId,
            createdAt: createdAt,
            duration: duration,
            instrumentColumnId: instrumentColumnId,
            title: "\(base) · \(sameDay + 1)",
            transcript: transcript?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyRecording,
            fileName: "\(id).m4a"
        )
        index.append(recording)
        saveIndex(index)
        protect(fileURL(for: recording))
        return recording
    }

    func updateTranscript(id: String, transcript: String) {
        var index = loadIndex()
        guard let position = index.firstIndex(where: { $0.id == id }) else { return }
        index[position].transcript = transcript
        saveIndex(index)
    }

    func delete(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var index = loadIndex()
        for recording in index where ids.contains(recording.id) {
            try? FileManager.default.removeItem(at: fileURL(for: recording))
        }
        index.removeAll { ids.contains($0.id) }
        saveIndex(index)
    }

    // MARK: Índice y protección

    private func loadIndex() -> [CourtVoiceRecording] {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([CourtVoiceRecording].self, from: data) else { return [] }
        return decoded
    }

    private func saveIndex(_ index: [CourtVoiceRecording]) {
        try? ensureDirectory(root)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: writeOptions)
        protect(indexURL)
    }

    private var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtectionUnlessOpen]
        #else
        return [.atomic]
        #endif
    }

    private func ensureDirectory(_ url: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUnlessOpen
        #endif
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
        protect(url)
    }

    /// Fuera de la copia de iCloud y, en iOS, cifrado mientras el dispositivo está bloqueado.
    private func protect(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        #endif
    }
}

private extension String {
    var nilIfEmptyRecording: String? { isEmpty ? nil : self }
}
