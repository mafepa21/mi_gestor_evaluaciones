abstract class BackupService {
  Future<String> createBackup();
  Future<List<String>> listBackups();
  Future<void> restoreBackup(String sourcePath);
}

class UnsupportedBackupService implements BackupService {
  @override
  Future<String> createBackup() {
    throw UnsupportedError('Las copias de seguridad no están disponibles aquí.');
  }

  @override
  Future<List<String>> listBackups() async => const <String>[];

  @override
  Future<void> restoreBackup(String sourcePath) {
    throw UnsupportedError('La restauración no está disponible aquí.');
  }
}

BackupService createBackupServiceImpl() => UnsupportedBackupService();
