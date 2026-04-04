import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/services/backup_service.dart';
import 'package:mi_gestor_evaluaciones/services/demo_data_service.dart';
import 'package:mi_gestor_evaluaciones/services/report_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return createBackupService();
});

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService();
});

final demoSeedProvider = Provider<DemoDataService>((ref) {
  return ref.watch(demoDataServiceProvider);
});
