import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/database/database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final alumnosProvider = StreamProvider.autoDispose<List<Alumno>>((ref) {
  return ref.watch(databaseProvider).watchAlumnos();
});

final clasesProvider = StreamProvider.autoDispose<List<Clase>>((ref) {
  return ref.watch(databaseProvider).watchClases();
});

final clasesResumenProvider =
    StreamProvider.autoDispose<List<ClaseResumen>>((ref) {
  return ref.watch(databaseProvider).watchClasesResumen();
});

final dashboardStatsProvider =
    StreamProvider.autoDispose<DashboardStats>((ref) {
  return ref.watch(databaseProvider).watchDashboardStats();
});

final alumnosDeClaseProvider =
    StreamProvider.autoDispose.family<List<Alumno>, int>((ref, claseId) {
  return ref.watch(databaseProvider).watchAlumnosByClase(claseId);
});

final planificacionProvider =
    StreamProvider.autoDispose<List<PeriodoConUnidades>>((ref) {
  return ref.watch(databaseProvider).watchPlanificacion();
});

final rubricasProvider =
    StreamProvider.autoDispose<List<RubricaCompleta>>((ref) {
  return ref.watch(databaseProvider).watchRubricasCompletas();
});

final evaluacionesDeClaseProvider =
    StreamProvider.autoDispose.family<List<Evaluacion>, int>((ref, claseId) {
  return ref.watch(databaseProvider).watchEvaluacionesByClase(claseId);
});

final cuadernoTabsProvider =
    StreamProvider.autoDispose.family<List<CuadernoTab>, int?>((ref, claseId) {
  if (claseId == null) return Stream.value(const <CuadernoTab>[]);
  return ref.watch(databaseProvider).watchCuadernoTabsByClase(claseId);
});

final cuadernoDataProvider =
    StreamProvider.autoDispose.family<CuadernoData?, int?>((ref, claseId) {
  return ref.watch(databaseProvider).watchCuadernoData(claseId);
});

final cuadernoViewProvider =
    Provider.autoDispose.family<AsyncValue<CuadernoView?>, int?>((ref, claseId) {
  final asyncData = ref.watch(cuadernoDataProvider(claseId));
  return asyncData.whenData((value) => value == null ? null : buildCuadernoView(value));
});
