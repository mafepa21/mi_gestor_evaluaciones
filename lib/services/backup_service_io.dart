import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mi_gestor_evaluaciones/services/backup_service_stub.dart';

export 'package:mi_gestor_evaluaciones/services/backup_service_stub.dart';

class LocalBackupService implements BackupService {
  static const _dbFileName = 'mi_gestor_evaluaciones.sqlite';

  @override
  Future<String> createBackup() async {
    final backupDir = await _backupsDirectory();
    final dbFile = await _dbFile();
    if (!dbFile.existsSync()) {
      throw StateError('La base de datos todavía no existe.');
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupFile = File(p.join(backupDir.path, 'backup_$timestamp.sqlite'));
    await backupFile.writeAsBytes(await dbFile.readAsBytes(), flush: true);
    return backupFile.path;
  }

  @override
  Future<List<String>> listBackups() async {
    final backupDir = await _backupsDirectory();
    final files = backupDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.sqlite'))
        .map((file) => file.path)
        .toList()
      ..sort((a, b) => b.compareTo(a));

    return files;
  }

  @override
  Future<void> restoreBackup(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw StateError('La copia seleccionada ya no existe.');
    }

    final target = await _dbFile();
    await target.parent.create(recursive: true);
    await target.writeAsBytes(await source.readAsBytes(), flush: true);
  }

  Future<File> _dbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _dbFileName));
  }

  Future<Directory> _backupsDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final backupDir = Directory(p.join(dir.path, 'backups'));
    await backupDir.create(recursive: true);
    return backupDir;
  }
}

BackupService createBackupServiceImpl() => LocalBackupService();
