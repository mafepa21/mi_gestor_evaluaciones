import 'package:mi_gestor_evaluaciones/services/backup_service_stub.dart';
import 'package:mi_gestor_evaluaciones/services/backup_service_stub.dart'
    if (dart.library.io) 'package:mi_gestor_evaluaciones/services/backup_service_io.dart'
    as impl;

export 'package:mi_gestor_evaluaciones/services/backup_service_stub.dart'
    if (dart.library.io) 'package:mi_gestor_evaluaciones/services/backup_service_io.dart';

BackupService createBackupService() => impl.createBackupServiceImpl();
