import CommonCrypto
import CryptoKit
import Foundation
import Security
import ZIPFoundation

enum ApplePortableBackupFormat: Equatable {
    case legacyPackage
    case encryptedV1

    static func detect(at url: URL, fileManager: FileManager = .default) throws -> Self {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw AppleEncryptedBackupError.invalidFormat
        }

        if isDirectory.boolValue {
            guard url.pathExtension.lowercased() == "migestorbackup" else {
                throw AppleEncryptedBackupError.invalidFormat
            }
            return .legacyPackage
        }

        guard url.pathExtension.lowercased() == "migestorbackupx" else {
            throw AppleEncryptedBackupError.invalidFormat
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.readExactly(AppleEncryptedBackupHeader.magic.count) == AppleEncryptedBackupHeader.magic else {
            throw AppleEncryptedBackupError.invalidFormat
        }
        return .encryptedV1
    }
}

enum AppleEncryptedBackupError: Error, Equatable, LocalizedError {
    case invalidFormat
    case unsupportedVersion
    case unsupportedAlgorithm
    case invalidParameters
    case passwordRequired
    case passwordTooLong
    case archiveTooLarge
    case authenticationFailed
    case truncatedFile
    case trailingData
    case unsafeArchiveEntry
    case tooManyEntries
    case extractedArchiveTooLarge
    case archiveEntryTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "El archivo no es una copia de Mi Gestor compatible."
        case .unsupportedVersion:
            return "Esta copia usa una versión de formato que la aplicación aún no admite."
        case .unsupportedAlgorithm:
            return "Esta copia usa un método de cifrado que la aplicación no admite."
        case .invalidParameters:
            return "La cabecera cifrada contiene parámetros no válidos."
        case .passwordRequired:
            return "Introduce la contraseña de esta copia."
        case .passwordTooLong:
            return "La contraseña supera el tamaño máximo admitido."
        case .archiveTooLarge:
            return "La copia supera el límite de tamaño seguro."
        case .authenticationFailed:
            return "La contraseña no es correcta o la copia ha sido modificada."
        case .truncatedFile:
            return "La copia está incompleta o truncada."
        case .trailingData:
            return "La copia contiene datos inesperados al final."
        case .unsafeArchiveEntry:
            return "La copia contiene una ruta o un tipo de archivo no seguro."
        case .tooManyEntries:
            return "La copia contiene demasiados archivos."
        case .extractedArchiveTooLarge:
            return "El contenido extraído supera el límite de tamaño seguro."
        case .archiveEntryTooLarge:
            return "Uno de los archivos de la copia supera el límite de tamaño seguro."
        }
    }
}

struct ApplePortableBackupLimits {
    static let archivePlaintextBytes: UInt64 = 2 * 1_024 * 1_024 * 1_024
    static let extractedBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024
    static let entryBytes: UInt64 = 1 * 1_024 * 1_024 * 1_024
    static let entryCount = 10_000
    static let passwordBytes = 1_024
    static let minimumIterations: UInt32 = 100_000
    static let maximumIterations: UInt32 = 2_000_000
    static let minimumChunkBytes: UInt32 = 64 * 1_024
    static let maximumChunkBytes: UInt32 = 4 * 1_024 * 1_024
}

struct AppleEncryptedBackupConfiguration {
    let iterations: UInt32
    let chunkSize: UInt32
    let minimumAcceptedIterations: UInt32
    let maximumAcceptedIterations: UInt32
    let maximumArchiveBytes: UInt64

    static let production = AppleEncryptedBackupConfiguration(
        iterations: 600_000,
        chunkSize: 1_024 * 1_024,
        minimumAcceptedIterations: ApplePortableBackupLimits.minimumIterations,
        maximumAcceptedIterations: ApplePortableBackupLimits.maximumIterations,
        maximumArchiveBytes: ApplePortableBackupLimits.archivePlaintextBytes
    )
}

struct AppleEncryptedBackupHeader: Equatable {
    static let magic = Data("MGEBKP01".utf8)
    static let encodedSize = 52
    static let version: UInt8 = 1
    static let kdfPBKDF2SHA256: UInt8 = 1
    static let cipherAES256GCMChunks: UInt8 = 1

    let iterations: UInt32
    let chunkSize: UInt32
    let plaintextSize: UInt64
    let salt: Data
    let noncePrefix: Data

    func encoded() throws -> Data {
        guard salt.count == 16, noncePrefix.count == 8 else {
            throw AppleEncryptedBackupError.invalidParameters
        }
        var data = Self.magic
        data.append(Self.version)
        data.append(Self.kdfPBKDF2SHA256)
        data.append(Self.cipherAES256GCMChunks)
        data.append(0)
        data.appendBigEndian(iterations)
        data.appendBigEndian(chunkSize)
        data.appendBigEndian(plaintextSize)
        data.append(salt)
        data.append(noncePrefix)
        return data
    }

    static func decode(_ data: Data, configuration: AppleEncryptedBackupConfiguration) throws -> Self {
        guard data.count == encodedSize, data.prefix(magic.count) == magic else {
            throw AppleEncryptedBackupError.invalidFormat
        }
        guard data[8] == version else { throw AppleEncryptedBackupError.unsupportedVersion }
        guard data[9] == kdfPBKDF2SHA256, data[10] == cipherAES256GCMChunks else {
            throw AppleEncryptedBackupError.unsupportedAlgorithm
        }
        guard data[11] == 0 else { throw AppleEncryptedBackupError.invalidParameters }

        let iterations = data.uint32BigEndian(at: 12)
        let chunkSize = data.uint32BigEndian(at: 16)
        let plaintextSize = data.uint64BigEndian(at: 20)
        guard iterations >= configuration.minimumAcceptedIterations,
              iterations <= configuration.maximumAcceptedIterations,
              chunkSize >= ApplePortableBackupLimits.minimumChunkBytes,
              chunkSize <= ApplePortableBackupLimits.maximumChunkBytes,
              plaintextSize > 0,
              plaintextSize <= configuration.maximumArchiveBytes else {
            throw AppleEncryptedBackupError.invalidParameters
        }

        return Self(
            iterations: iterations,
            chunkSize: chunkSize,
            plaintextSize: plaintextSize,
            salt: data.subdata(in: 28..<44),
            noncePrefix: data.subdata(in: 44..<52)
        )
    }
}

enum ApplePasswordKeyDerivation {
    static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        guard !passwordBytes.isEmpty else { throw AppleEncryptedBackupError.passwordRequired }
        guard passwordBytes.count <= ApplePortableBackupLimits.passwordBytes else {
            throw AppleEncryptedBackupError.passwordTooLong
        }
        guard !salt.isEmpty else { throw AppleEncryptedBackupError.invalidParameters }

        var derivedKey = [UInt8](repeating: 0, count: 32)
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                    passwordBytes.count,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &derivedKey,
                    derivedKey.count
                )
            }
        }
        guard status == kCCSuccess else { throw AppleEncryptedBackupError.invalidParameters }
        defer { _ = derivedKey.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        return SymmetricKey(data: derivedKey)
    }
}

enum AppleEncryptedBackupContainer {
    static func encrypt(
        plaintextURL: URL,
        destinationURL: URL,
        password: String,
        configuration: AppleEncryptedBackupConfiguration = .production
    ) throws {
        let plaintextSize = try plaintextURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(UInt64.init) ?? 0
        guard plaintextSize > 0, plaintextSize <= configuration.maximumArchiveBytes else {
            throw AppleEncryptedBackupError.archiveTooLarge
        }
        guard configuration.iterations >= configuration.minimumAcceptedIterations,
              configuration.iterations <= configuration.maximumAcceptedIterations,
              configuration.chunkSize >= ApplePortableBackupLimits.minimumChunkBytes,
              configuration.chunkSize <= ApplePortableBackupLimits.maximumChunkBytes else {
            throw AppleEncryptedBackupError.invalidParameters
        }

        let salt = try secureRandomData(count: 16)
        let noncePrefix = try secureRandomData(count: 8)
        let header = AppleEncryptedBackupHeader(
            iterations: configuration.iterations,
            chunkSize: configuration.chunkSize,
            plaintextSize: plaintextSize,
            salt: salt,
            noncePrefix: noncePrefix
        )
        let headerData = try header.encoded()
        let key = try ApplePasswordKeyDerivation.deriveKey(
            password: password,
            salt: salt,
            iterations: configuration.iterations
        )

        let input = try FileHandle(forReadingFrom: plaintextURL)
        defer { try? input.close() }
        guard !FileManager.default.fileExists(atPath: destinationURL.path),
              FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw AppleEncryptedBackupError.invalidParameters
        }
        let output = try FileHandle(forWritingTo: destinationURL)
        var succeeded = false
        defer {
            try? output.close()
            if !succeeded { try? FileManager.default.removeItem(at: destinationURL) }
        }

        try output.write(contentsOf: headerData)
        var processed: UInt64 = 0
        var chunkIndex: UInt32 = 0
        while processed < plaintextSize {
            let requested = Int(min(UInt64(configuration.chunkSize), plaintextSize - processed))
            let plaintext = try input.readExactly(requested)
            let plaintextLength = UInt32(plaintext.count)
            let nonce = try AES.GCM.Nonce(data: nonceData(prefix: noncePrefix, chunkIndex: chunkIndex))
            let sealed = try AES.GCM.seal(
                plaintext,
                using: key,
                nonce: nonce,
                authenticating: authenticatedData(header: headerData, chunkIndex: chunkIndex, plaintextLength: plaintextLength)
            )
            var lengthData = Data()
            lengthData.appendBigEndian(plaintextLength)
            try output.write(contentsOf: lengthData)
            try output.write(contentsOf: sealed.ciphertext)
            try output.write(contentsOf: sealed.tag)
            processed += UInt64(plaintext.count)
            guard chunkIndex < UInt32.max || processed == plaintextSize else {
                throw AppleEncryptedBackupError.archiveTooLarge
            }
            chunkIndex &+= 1
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else {
            throw AppleEncryptedBackupError.archiveTooLarge
        }
        try output.synchronize()
        succeeded = true
    }

    static func decrypt(
        encryptedURL: URL,
        destinationURL: URL,
        password: String,
        configuration: AppleEncryptedBackupConfiguration = .production
    ) throws {
        let encryptedSize = try encryptedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(UInt64.init) ?? 0
        let maximumRecords = configuration.maximumArchiveBytes / UInt64(ApplePortableBackupLimits.minimumChunkBytes) + 1
        let maximumEncryptedSize = configuration.maximumArchiveBytes + UInt64(AppleEncryptedBackupHeader.encodedSize) + maximumRecords * 20
        guard encryptedSize <= maximumEncryptedSize else { throw AppleEncryptedBackupError.archiveTooLarge }

        let input = try FileHandle(forReadingFrom: encryptedURL)
        defer { try? input.close() }
        let headerData = try input.readExactly(AppleEncryptedBackupHeader.encodedSize)
        let header = try AppleEncryptedBackupHeader.decode(headerData, configuration: configuration)
        let key = try ApplePasswordKeyDerivation.deriveKey(
            password: password,
            salt: header.salt,
            iterations: header.iterations
        )

        guard !FileManager.default.fileExists(atPath: destinationURL.path),
              FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw AppleEncryptedBackupError.invalidParameters
        }
        let output = try FileHandle(forWritingTo: destinationURL)
        var succeeded = false
        defer {
            try? output.close()
            if !succeeded { try? FileManager.default.removeItem(at: destinationURL) }
        }

        var processed: UInt64 = 0
        var chunkIndex: UInt32 = 0
        while processed < header.plaintextSize {
            let lengthData = try input.readExactly(4)
            let plaintextLength = lengthData.uint32BigEndian(at: 0)
            let remaining = header.plaintextSize - processed
            guard plaintextLength > 0,
                  plaintextLength <= header.chunkSize,
                  UInt64(plaintextLength) <= remaining,
                  (remaining > UInt64(header.chunkSize) ? plaintextLength == header.chunkSize : UInt64(plaintextLength) == remaining) else {
                throw AppleEncryptedBackupError.invalidFormat
            }
            let ciphertext = try input.readExactly(Int(plaintextLength))
            let tag = try input.readExactly(16)
            let nonce = try AES.GCM.Nonce(data: nonceData(prefix: header.noncePrefix, chunkIndex: chunkIndex))
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            do {
                let plaintext = try AES.GCM.open(
                    sealedBox,
                    using: key,
                    authenticating: authenticatedData(
                        header: headerData,
                        chunkIndex: chunkIndex,
                        plaintextLength: plaintextLength
                    )
                )
                try output.write(contentsOf: plaintext)
            } catch {
                throw AppleEncryptedBackupError.authenticationFailed
            }
            processed += UInt64(plaintextLength)
            guard chunkIndex < UInt32.max || processed == header.plaintextSize else {
                throw AppleEncryptedBackupError.invalidFormat
            }
            chunkIndex &+= 1
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else {
            throw AppleEncryptedBackupError.trailingData
        }
        try output.synchronize()
        succeeded = true
    }

    private static func authenticatedData(
        header: Data,
        chunkIndex: UInt32,
        plaintextLength: UInt32
    ) -> Data {
        var data = header
        data.appendBigEndian(chunkIndex)
        data.appendBigEndian(plaintextLength)
        return data
    }

    private static func nonceData(prefix: Data, chunkIndex: UInt32) -> Data {
        var data = prefix
        data.appendBigEndian(chunkIndex)
        return data
    }

    private static func secureRandomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw AppleEncryptedBackupError.invalidParameters }
        return data
    }
}

enum AppleBackupPackageArchive {
    static func createArchive(
        packageURL: URL,
        archiveURL: URL,
        fileManager: FileManager = .default
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppleEncryptedBackupError.invalidFormat
        }
        guard try packageURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw AppleEncryptedBackupError.unsafeArchiveEntry
        }
        let packageRoot = packageURL.standardizedFileURL.resolvingSymlinksInPath()
        guard !fileManager.fileExists(atPath: archiveURL.path) else {
            throw AppleEncryptedBackupError.invalidParameters
        }
        let archive = try Archive(url: archiveURL, accessMode: .create)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: packageRoot,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            throw AppleEncryptedBackupError.invalidFormat
        }

        var entries: [(url: URL, relativePath: String, isDirectory: Bool, size: UInt64)] = []
        var totalSize: UInt64 = 0
        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw AppleEncryptedBackupError.unsafeArchiveEntry }
            let resolved = item.standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path == packageRoot.path || resolved.path.hasPrefix(packageRoot.path + "/") else {
                throw AppleEncryptedBackupError.unsafeArchiveEntry
            }
            let relativePath = String(resolved.path.dropFirst(packageRoot.path.count + 1))
            try validateRelativePath(relativePath)
            let isDirectory = values.isDirectory == true
            guard isDirectory || values.isRegularFile == true else {
                throw AppleEncryptedBackupError.unsafeArchiveEntry
            }
            let size = isDirectory ? 0 : UInt64(values.fileSize ?? 0)
            guard size <= ApplePortableBackupLimits.entryBytes else {
                throw AppleEncryptedBackupError.archiveEntryTooLarge
            }
            let (nextTotal, overflow) = totalSize.addingReportingOverflow(size)
            guard !overflow, nextTotal <= ApplePortableBackupLimits.extractedBytes else {
                throw AppleEncryptedBackupError.extractedArchiveTooLarge
            }
            totalSize = nextTotal
            entries.append((resolved, relativePath, isDirectory, size))
            guard entries.count <= ApplePortableBackupLimits.entryCount else {
                throw AppleEncryptedBackupError.tooManyEntries
            }
        }

        for entry in entries.sorted(by: { $0.relativePath < $1.relativePath }) {
            let path = entry.isDirectory ? entry.relativePath + "/" : entry.relativePath
            try archive.addEntry(
                with: path,
                relativeTo: packageRoot,
                compressionMethod: entry.isDirectory ? .none : .deflate,
                bufferSize: 1_024 * 1_024
            )
        }
        let size = try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(UInt64.init) ?? 0
        guard size <= ApplePortableBackupLimits.archivePlaintextBytes else {
            try? fileManager.removeItem(at: archiveURL)
            throw AppleEncryptedBackupError.archiveTooLarge
        }
    }

    static func extractArchive(
        archiveURL: URL,
        destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let archiveSize = try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(UInt64.init) ?? 0
        guard archiveSize <= ApplePortableBackupLimits.archivePlaintextBytes else {
            throw AppleEncryptedBackupError.archiveTooLarge
        }
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let entries = Array(archive)
        guard entries.count <= ApplePortableBackupLimits.entryCount else {
            throw AppleEncryptedBackupError.tooManyEntries
        }

        var seenPaths = Set<String>()
        var declaredTotal: UInt64 = 0
        for entry in entries {
            let canonicalPath = try canonicalRelativePath(entry.path)
            guard entry.type != .symlink, seenPaths.insert(canonicalPath).inserted else {
                throw AppleEncryptedBackupError.unsafeArchiveEntry
            }
            guard entry.uncompressedSize <= ApplePortableBackupLimits.entryBytes else {
                throw AppleEncryptedBackupError.archiveEntryTooLarge
            }
            let (nextTotal, overflow) = declaredTotal.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, nextTotal <= ApplePortableBackupLimits.extractedBytes else {
                throw AppleEncryptedBackupError.extractedArchiveTooLarge
            }
            declaredTotal = nextTotal
        }

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw AppleEncryptedBackupError.invalidParameters
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        var succeeded = false
        defer {
            if !succeeded { try? fileManager.removeItem(at: destinationURL) }
        }
        let destinationRoot = destinationURL.standardizedFileURL
        for entry in entries {
            let target = destinationRoot.appendingPathComponent(entry.path).standardizedFileURL
            guard target.path.hasPrefix(destinationRoot.path + "/") else {
                throw AppleEncryptedBackupError.unsafeArchiveEntry
            }
            _ = try archive.extract(
                entry,
                to: target,
                bufferSize: 1_024 * 1_024,
                skipCRC32: false,
                allowUncontainedSymlinks: false
            )
        }
        try validateExtractedTree(at: destinationRoot, fileManager: fileManager)
        succeeded = true
    }

    private static func validateExtractedTree(at root: URL, fileManager: FileManager) throws {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else { throw AppleEncryptedBackupError.invalidFormat }
        var count = 0
        var total: UInt64 = 0
        while let item = enumerator.nextObject() as? URL {
            count += 1
            guard count <= ApplePortableBackupLimits.entryCount else {
                throw AppleEncryptedBackupError.tooManyEntries
            }
            let values = try item.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true,
                  values.isRegularFile == true || values.isDirectory == true else {
                throw AppleEncryptedBackupError.unsafeArchiveEntry
            }
            let size = values.isRegularFile == true ? UInt64(values.fileSize ?? 0) : 0
            guard size <= ApplePortableBackupLimits.entryBytes else {
                throw AppleEncryptedBackupError.archiveEntryTooLarge
            }
            let (nextTotal, overflow) = total.addingReportingOverflow(size)
            guard !overflow, nextTotal <= ApplePortableBackupLimits.extractedBytes else {
                throw AppleEncryptedBackupError.extractedArchiveTooLarge
            }
            total = nextTotal
        }
    }

    static func validateRelativePath(_ path: String) throws {
        _ = try canonicalRelativePath(path)
    }

    private static func canonicalRelativePath(_ path: String) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.utf8.contains(0) else {
            throw AppleEncryptedBackupError.unsafeArchiveEntry
        }
        let canonicalPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        let components = canonicalPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw AppleEncryptedBackupError.unsafeArchiveEntry
        }
        return canonicalPath
    }
}

private extension FileHandle {
    func readExactly(_ count: Int) throws -> Data {
        guard count >= 0 else { throw AppleEncryptedBackupError.invalidParameters }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            guard let chunk = try read(upToCount: count - result.count), !chunk.isEmpty else {
                throw AppleEncryptedBackupError.truncatedFile
            }
            result.append(chunk)
        }
        return result
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendBigEndian(_ value: UInt64) {
        append(UInt8((value >> 56) & 0xff))
        append(UInt8((value >> 48) & 0xff))
        append(UInt8((value >> 40) & 0xff))
        append(UInt8((value >> 32) & 0xff))
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    func uint32BigEndian(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func uint64BigEndian(at offset: Int) -> UInt64 {
        (UInt64(self[offset]) << 56)
            | (UInt64(self[offset + 1]) << 48)
            | (UInt64(self[offset + 2]) << 40)
            | (UInt64(self[offset + 3]) << 32)
            | (UInt64(self[offset + 4]) << 24)
            | (UInt64(self[offset + 5]) << 16)
            | (UInt64(self[offset + 6]) << 8)
            | UInt64(self[offset + 7])
    }
}
