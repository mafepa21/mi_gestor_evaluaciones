import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:mi_gestor_evaluaciones/core/formula_evaluator.dart';
import 'package:rxdart/rxdart.dart';

part 'database.g.dart';

typedef Evaluacion = Evaluacione;
typedef Calificacion = Calificacione;
typedef RubricaSeleccion = RubricaEvaluacione;
typedef CuadernoTab = CuadernoTabData;

class Alumnos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  TextColumn get apellidos => text()();
  TextColumn get email => text().nullable()();
  TextColumn get fotoPath => text().nullable()();
}

class Clases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  IntColumn get curso => integer()();
  TextColumn get descripcion => text().nullable()();
}

class AlumnoClase extends Table {
  IntColumn get alumnoId =>
      integer().references(Alumnos, #id, onDelete: KeyAction.cascade)();
  IntColumn get claseId =>
      integer().references(Clases, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {alumnoId, claseId};
}

class Periodos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  DateTimeColumn get fechaInicio => dateTime()();
  DateTimeColumn get fechaFin => dateTime()();
}

class UnidadesDidacticas extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get periodoId =>
      integer().references(Periodos, #id, onDelete: KeyAction.cascade)();
  TextColumn get titulo => text()();
  TextColumn get objetivos => text()();
  TextColumn get competencias => text()();
}

class Sesiones extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get unidadId => integer()
      .references(UnidadesDidacticas, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get fecha => dateTime()();
  TextColumn get descripcion => text()();
}

class Rubricas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  TextColumn get descripcion => text().nullable()();
}

class CriteriosRubrica extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get rubricaId =>
      integer().references(Rubricas, #id, onDelete: KeyAction.cascade)();
  TextColumn get descripcion => text()();
  RealColumn get peso => real()();
  IntColumn get orden => integer().withDefault(const Constant(0))();
}

class NivelesRubrica extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get criterioId => integer()
      .references(CriteriosRubrica, #id, onDelete: KeyAction.cascade)();
  TextColumn get nivel => text()();
  IntColumn get puntos => integer()();
  TextColumn get descripcion => text().nullable()();
  IntColumn get orden => integer().withDefault(const Constant(0))();
}

class Evaluaciones extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get claseId =>
      integer().references(Clases, #id, onDelete: KeyAction.cascade)();
  TextColumn get nombre => text()();
  TextColumn get codigo => text()();
  TextColumn get tipo => text()();
  RealColumn get peso => real().withDefault(const Constant(1))();
  TextColumn get formula => text().nullable()();
  IntColumn get rubricaId =>
      integer().references(Rubricas, #id).nullable()();
  IntColumn get tabId =>
      integer().references(CuadernoTabs, #id, onDelete: KeyAction.setNull).nullable()();
  IntColumn get orden => integer().withDefault(const Constant(0))();
  TextColumn get descripcion => text().nullable()();
}

class CuadernoTabs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get claseId =>
      integer().references(Clases, #id, onDelete: KeyAction.cascade)();
  TextColumn get nombre => text()();
  IntColumn get orden => integer().withDefault(const Constant(0))();
}

class Calificaciones extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get alumnoId =>
      integer().references(Alumnos, #id, onDelete: KeyAction.cascade)();
  IntColumn get evaluacionId =>
      integer().references(Evaluaciones, #id, onDelete: KeyAction.cascade)();
  RealColumn get valor => real().nullable()();
  TextColumn get evidencia => text().nullable()();
  TextColumn get evidenciaPath => text().nullable()();
  DateTimeColumn get fecha => dateTime()();
}

class RubricaEvaluaciones extends Table {
  IntColumn get alumnoId =>
      integer().references(Alumnos, #id, onDelete: KeyAction.cascade)();
  IntColumn get evaluacionId =>
      integer().references(Evaluaciones, #id, onDelete: KeyAction.cascade)();
  IntColumn get criterioId => integer()
      .references(CriteriosRubrica, #id, onDelete: KeyAction.cascade)();
  IntColumn get nivelId =>
      integer().references(NivelesRubrica, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get fecha => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {alumnoId, evaluacionId, criterioId};
}

class Asistencia extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get alumnoId =>
      integer().references(Alumnos, #id, onDelete: KeyAction.cascade)();
  IntColumn get claseId =>
      integer().references(Clases, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get fecha => dateTime()();
  TextColumn get estado => text()();
}

@DriftDatabase(
  tables: [
    Alumnos,
    Clases,
    AlumnoClase,
    Periodos,
    UnidadesDidacticas,
    Sesiones,
    Rubricas,
    CriteriosRubrica,
    NivelesRubrica,
    Evaluaciones,
    CuadernoTabs,
    Calificaciones,
    RubricaEvaluaciones,
    Asistencia,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor})
      : super(
          executor ??
              driftDatabase(
                name: 'mi_gestor_evaluaciones',
              ),
        );

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(rubricaEvaluaciones);
          }
          if (from < 3) {
            await m.createTable(cuadernoTabs);
            await m.addColumn(evaluaciones, evaluaciones.tabId);
            await m.addColumn(evaluaciones, evaluaciones.orden);

            await customStatement('''
              INSERT INTO cuaderno_tabs (clase_id, nombre, orden)
              SELECT id, 'General', 0 FROM clases
            ''');

            await customStatement('''
              UPDATE evaluaciones
              SET tab_id = (
                SELECT ct.id
                FROM cuaderno_tabs ct
                WHERE ct.clase_id = evaluaciones.clase_id
                ORDER BY ct.orden, ct.id
                LIMIT 1
              )
              WHERE tab_id IS NULL
            ''');

            await customStatement('''
              UPDATE evaluaciones
              SET orden = id
              WHERE orden = 0
            ''');
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Stream<List<Alumno>> watchAlumnos() {
    final query = select(alumnos)
      ..orderBy([
        (t) => OrderingTerm.asc(t.apellidos),
        (t) => OrderingTerm.asc(t.nombre),
      ]);
    return query.watch();
  }

  Future<List<Alumno>> getAlumnosList() {
    final query = select(alumnos)
      ..orderBy([
        (t) => OrderingTerm.asc(t.apellidos),
        (t) => OrderingTerm.asc(t.nombre),
      ]);
    return query.get();
  }

  Future<int> saveAlumno({
    int? id,
    required String nombre,
    required String apellidos,
    String? email,
    String? fotoPath,
  }) async {
    final companion = AlumnosCompanion(
      id: id == null ? const Value.absent() : Value(id),
      nombre: Value(nombre),
      apellidos: Value(apellidos),
      email: Value(email),
      fotoPath: Value(fotoPath),
    );

    return into(alumnos).insertOnConflictUpdate(companion);
  }

  Future<void> deleteAlumnoById(int alumnoId) async {
    await (delete(alumnos)..where((t) => t.id.equals(alumnoId))).go();
  }

  Stream<List<Clase>> watchClases() {
    final query = select(clases)
      ..orderBy([
        (t) => OrderingTerm.asc(t.curso),
        (t) => OrderingTerm.asc(t.nombre),
      ]);
    return query.watch();
  }

  Stream<List<ClaseResumen>> watchClasesResumen() {
    return Rx.combineLatest2(
      watchClases(),
      select(alumnoClase).watch(),
      (List<Clase> clasesData, List<AlumnoClaseData> relaciones) {
        final countByClass = <int, int>{};
        for (final relacion in relaciones) {
          countByClass.update(relacion.claseId, (value) => value + 1,
              ifAbsent: () => 1);
        }

        return clasesData
            .map(
              (clase) => ClaseResumen(
                clase: clase,
                totalAlumnos: countByClass[clase.id] ?? 0,
              ),
            )
            .toList();
      },
    );
  }

  Future<int> saveClase({
    int? id,
    required String nombre,
    required int curso,
    String? descripcion,
  }) async {
    final companion = ClasesCompanion(
      id: id == null ? const Value.absent() : Value(id),
      nombre: Value(nombre),
      curso: Value(curso),
      descripcion: Value(descripcion),
    );

    return into(clases).insertOnConflictUpdate(companion);
  }

  Future<void> deleteClaseById(int claseId) async {
    await (delete(clases)..where((t) => t.id.equals(claseId))).go();
  }

  Stream<List<Alumno>> watchAlumnosByClase(int claseId) {
    final query = select(alumnos).join([
      innerJoin(alumnoClase, alumnoClase.alumnoId.equalsExp(alumnos.id)),
    ])
      ..where(alumnoClase.claseId.equals(claseId))
      ..orderBy([
        OrderingTerm.asc(alumnos.apellidos),
        OrderingTerm.asc(alumnos.nombre),
      ]);

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(alumnos)).toList(),
    );
  }

  Future<List<Alumno>> getAlumnosByClaseList(int claseId) async {
    final query = select(alumnos).join([
      innerJoin(alumnoClase, alumnoClase.alumnoId.equalsExp(alumnos.id)),
    ])
      ..where(alumnoClase.claseId.equals(claseId))
      ..orderBy([
        OrderingTerm.asc(alumnos.apellidos),
        OrderingTerm.asc(alumnos.nombre),
      ]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(alumnos)).toList();
  }

  Future<void> assignAlumnoToClase(int alumnoId, int claseId) async {
    await into(alumnoClase).insert(
      AlumnoClaseCompanion(
        alumnoId: Value(alumnoId),
        claseId: Value(claseId),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> removeAlumnoFromClase(int alumnoId, int claseId) async {
    await (delete(alumnoClase)
          ..where((t) => t.alumnoId.equals(alumnoId) & t.claseId.equals(claseId)))
        .go();
  }

  Stream<List<Periodo>> watchPeriodos() {
    final query = select(periodos)
      ..orderBy([(t) => OrderingTerm.asc(t.fechaInicio)]);
    return query.watch();
  }

  Future<int> savePeriodo({
    int? id,
    required String nombre,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    final companion = PeriodosCompanion(
      id: id == null ? const Value.absent() : Value(id),
      nombre: Value(nombre),
      fechaInicio: Value(fechaInicio),
      fechaFin: Value(fechaFin),
    );

    return into(periodos).insertOnConflictUpdate(companion);
  }

  Future<void> deletePeriodoById(int periodoId) async {
    await (delete(periodos)..where((t) => t.id.equals(periodoId))).go();
  }

  Stream<List<PeriodoConUnidades>> watchPlanificacion() {
    return Rx.combineLatest3(
      watchPeriodos(),
      select(unidadesDidacticas).watch(),
      select(sesiones).watch(),
      (
        List<Periodo> periodosData,
        List<UnidadesDidactica> unidadesData,
        List<Sesione> sesionesData,
      ) {
        final sesionesPorUnidad = <int, List<Sesione>>{};
        for (final sesion in sesionesData) {
          sesionesPorUnidad
              .putIfAbsent(sesion.unidadId, () => <Sesione>[])
              .add(sesion);
        }

        final unidadesPorPeriodo = <int, List<UnidadConSesiones>>{};
        for (final unidad in unidadesData) {
          unidadesPorPeriodo
              .putIfAbsent(unidad.periodoId, () => <UnidadConSesiones>[])
              .add(
                UnidadConSesiones(
                  unidad: unidad,
                  sesiones: [...?sesionesPorUnidad[unidad.id]]
                    ..sort((a, b) => a.fecha.compareTo(b.fecha)),
                ),
              );
        }

        return periodosData
            .map(
              (periodo) => PeriodoConUnidades(
                periodo: periodo,
                unidades: [...?unidadesPorPeriodo[periodo.id]]
                  ..sort(
                    (a, b) => a.unidad.titulo.compareTo(b.unidad.titulo),
                  ),
              ),
            )
            .toList();
      },
    );
  }

  Future<int> saveUnidad({
    int? id,
    required int periodoId,
    required String titulo,
    required String objetivos,
    required String competencias,
  }) async {
    final companion = UnidadesDidacticasCompanion(
      id: id == null ? const Value.absent() : Value(id),
      periodoId: Value(periodoId),
      titulo: Value(titulo),
      objetivos: Value(objetivos),
      competencias: Value(competencias),
    );

    return into(unidadesDidacticas).insertOnConflictUpdate(companion);
  }

  Future<void> deleteUnidadById(int unidadId) async {
    await (delete(unidadesDidacticas)..where((t) => t.id.equals(unidadId))).go();
  }

  Future<int> saveSesion({
    int? id,
    required int unidadId,
    required DateTime fecha,
    required String descripcion,
  }) async {
    final companion = SesionesCompanion(
      id: id == null ? const Value.absent() : Value(id),
      unidadId: Value(unidadId),
      fecha: Value(fecha),
      descripcion: Value(descripcion),
    );

    return into(sesiones).insertOnConflictUpdate(companion);
  }

  Future<void> deleteSesionById(int sesionId) async {
    await (delete(sesiones)..where((t) => t.id.equals(sesionId))).go();
  }

  Stream<List<RubricaCompleta>> watchRubricasCompletas() {
    return Rx.combineLatest3(
      select(rubricas).watch(),
      select(criteriosRubrica).watch(),
      select(nivelesRubrica).watch(),
      (
        List<Rubrica> rubricasData,
        List<CriteriosRubricaData> criteriosData,
        List<NivelesRubricaData> nivelesData,
      ) {
        final nivelesPorCriterio = <int, List<NivelesRubricaData>>{};
        for (final nivel in nivelesData) {
          nivelesPorCriterio
              .putIfAbsent(nivel.criterioId, () => <NivelesRubricaData>[])
              .add(nivel);
        }

        final criteriosPorRubrica = <int, List<CriterioConNiveles>>{};
        for (final criterio in criteriosData) {
          criteriosPorRubrica
              .putIfAbsent(criterio.rubricaId, () => <CriterioConNiveles>[])
              .add(
                CriterioConNiveles(
                  criterio: criterio,
                  niveles: [...?nivelesPorCriterio[criterio.id]]
                    ..sort((a, b) => a.orden.compareTo(b.orden)),
                ),
              );
        }

        return rubricasData
            .map(
              (rubrica) => RubricaCompleta(
                rubrica: rubrica,
                criterios: [...?criteriosPorRubrica[rubrica.id]]
                  ..sort((a, b) => a.criterio.orden.compareTo(b.criterio.orden)),
              ),
            )
            .toList();
      },
    );
  }

  Future<int> saveRubrica({
    int? id,
    required String nombre,
    String? descripcion,
  }) async {
    final companion = RubricasCompanion(
      id: id == null ? const Value.absent() : Value(id),
      nombre: Value(nombre),
      descripcion: Value(descripcion),
    );

    return into(rubricas).insertOnConflictUpdate(companion);
  }

  Future<void> deleteRubricaById(int rubricaId) async {
    await (delete(rubricas)..where((t) => t.id.equals(rubricaId))).go();
  }

  Future<int> saveCriterio({
    int? id,
    required int rubricaId,
    required String descripcion,
    required double peso,
    required int orden,
  }) async {
    final companion = CriteriosRubricaCompanion(
      id: id == null ? const Value.absent() : Value(id),
      rubricaId: Value(rubricaId),
      descripcion: Value(descripcion),
      peso: Value(peso),
      orden: Value(orden),
    );

    return into(criteriosRubrica).insertOnConflictUpdate(companion);
  }

  Future<void> deleteCriterioById(int criterioId) async {
    await (delete(criteriosRubrica)..where((t) => t.id.equals(criterioId))).go();
  }

  Future<int> saveNivel({
    int? id,
    required int criterioId,
    required String nivel,
    required int puntos,
    String? descripcion,
    required int orden,
  }) async {
    final companion = NivelesRubricaCompanion(
      id: id == null ? const Value.absent() : Value(id),
      criterioId: Value(criterioId),
      nivel: Value(nivel),
      puntos: Value(puntos),
      descripcion: Value(descripcion),
      orden: Value(orden),
    );

    return into(nivelesRubrica).insertOnConflictUpdate(companion);
  }

  Future<void> deleteNivelById(int nivelId) async {
    await (delete(nivelesRubrica)..where((t) => t.id.equals(nivelId))).go();
  }

  Future<RubricaCompleta?> getRubricaCompletaById(int rubricaId) async {
    final rubrica = await (select(rubricas)..where((t) => t.id.equals(rubricaId)))
        .getSingleOrNull();
    if (rubrica == null) {
      return null;
    }

    final criterios = await (select(criteriosRubrica)
          ..where((t) => t.rubricaId.equals(rubricaId))
          ..orderBy([(t) => OrderingTerm.asc(t.orden)]))
        .get();

    if (criterios.isEmpty) {
      return RubricaCompleta(
        rubrica: rubrica,
        criterios: const [],
      );
    }

    final niveles = await (select(nivelesRubrica)
          ..where((t) => t.criterioId.isIn(criterios.map((item) => item.id)))
          ..orderBy([(t) => OrderingTerm.asc(t.orden)]))
        .get();

    final nivelesPorCriterio = <int, List<NivelesRubricaData>>{};
    for (final nivel in niveles) {
      nivelesPorCriterio.putIfAbsent(nivel.criterioId, () => []).add(nivel);
    }

    return RubricaCompleta(
      rubrica: rubrica,
      criterios: criterios
          .map(
            (criterio) => CriterioConNiveles(
              criterio: criterio,
              niveles: nivelesPorCriterio[criterio.id] ?? const [],
            ),
          )
          .toList(),
    );
  }

  Stream<List<Evaluacion>> watchEvaluacionesByClase(int claseId) {
    final query = select(evaluaciones)
      ..where((t) => t.claseId.equals(claseId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.tabId),
        (t) => OrderingTerm.asc(t.orden),
        (t) => OrderingTerm.asc(t.nombre),
      ]);
    return query.watch();
  }

  Stream<List<CuadernoTab>> watchCuadernoTabsByClase(int claseId) {
    final query = select(cuadernoTabs)
      ..where((t) => t.claseId.equals(claseId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.orden),
        (t) => OrderingTerm.asc(t.id),
      ]);
    return query.watch();
  }

  Future<List<CuadernoTab>> getCuadernoTabsByClaseList(int claseId) {
    final query = select(cuadernoTabs)
      ..where((t) => t.claseId.equals(claseId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.orden),
        (t) => OrderingTerm.asc(t.id),
      ]);
    return query.get();
  }

  Future<int> ensureDefaultCuadernoTab(int claseId) async {
    final existing = await (select(cuadernoTabs)
          ..where((t) => t.claseId.equals(claseId))
          ..orderBy([(t) => OrderingTerm.asc(t.orden), (t) => OrderingTerm.asc(t.id)]))
        .getSingleOrNull();
    if (existing != null) {
      return existing.id;
    }

    return into(cuadernoTabs).insert(
      CuadernoTabsCompanion.insert(
        claseId: claseId,
        nombre: 'General',
        orden: const Value(0),
      ),
    );
  }

  Future<int> saveCuadernoTab({
    int? id,
    required int claseId,
    required String nombre,
    int? orden,
  }) async {
    final normalizedName = nombre.trim().isEmpty ? 'Pestaña' : nombre.trim();
    final targetOrder = orden ??
        await ((selectOnly(cuadernoTabs)
              ..addColumns([cuadernoTabs.orden.max()])
              ..where(cuadernoTabs.claseId.equals(claseId)))
            .map((row) => row.read(cuadernoTabs.orden.max()) ?? -1)
            .getSingle()) +
            1;

    return into(cuadernoTabs).insertOnConflictUpdate(
      CuadernoTabsCompanion(
        id: id == null ? const Value.absent() : Value(id),
        claseId: Value(claseId),
        nombre: Value(normalizedName),
        orden: Value(targetOrder),
      ),
    );
  }

  Future<void> deleteCuadernoTabById(int tabId) async {
    await transaction(() async {
      final tab = await (select(cuadernoTabs)..where((t) => t.id.equals(tabId)))
          .getSingleOrNull();
      if (tab == null) return;

      final remainingTabs = await (select(cuadernoTabs)
            ..where((t) => t.claseId.equals(tab.claseId) & t.id.isNotValue(tabId))
            ..orderBy([(t) => OrderingTerm.asc(t.orden), (t) => OrderingTerm.asc(t.id)]))
          .get();

      final fallbackTabId = if (remainingTabs.isNotEmpty)
        remainingTabs.first.id
      else
        await saveCuadernoTab(
          claseId: tab.claseId,
          nombre: 'General',
          orden: 0,
        );

      await (update(evaluaciones)..where((t) => t.tabId.equals(tabId))).write(
        EvaluacionesCompanion(tabId: Value(fallbackTabId)),
      );

      await (delete(cuadernoTabs)..where((t) => t.id.equals(tabId))).go();
    });
  }

  Future<int> saveEvaluacion({
    int? id,
    required int claseId,
    required String nombre,
    required String codigo,
    required String tipo,
    required double peso,
    String? formula,
    int? rubricaId,
    int? tabId,
    int? orden,
    String? descripcion,
  }) async {
    final resolvedTabId = tabId ?? await ensureDefaultCuadernoTab(claseId);
    final resolvedOrder = orden ??
        await ((selectOnly(evaluaciones)
              ..addColumns([evaluaciones.orden.max()])
              ..where(
                evaluaciones.claseId.equals(claseId) &
                    evaluaciones.tabId.equals(resolvedTabId),
              ))
            .map((row) => row.read(evaluaciones.orden.max()) ?? -1)
            .getSingle()) +
            1;

    final companion = EvaluacionesCompanion(
      id: id == null ? const Value.absent() : Value(id),
      claseId: Value(claseId),
      nombre: Value(nombre),
      codigo: Value(codigo),
      tipo: Value(tipo),
      peso: Value(peso),
      formula: Value(formula),
      rubricaId: Value(rubricaId),
      tabId: Value(resolvedTabId),
      orden: Value(resolvedOrder),
      descripcion: Value(descripcion),
    );

    return into(evaluaciones).insertOnConflictUpdate(companion);
  }

  Future<void> deleteEvaluacionById(int evaluacionId) async {
    await (delete(evaluaciones)..where((t) => t.id.equals(evaluacionId))).go();
  }

  Stream<List<Calificacion>> watchCalificacionesByClase(int claseId) {
    final evaluacionesDeClase = selectOnly(evaluaciones)
      ..addColumns([evaluaciones.id])
      ..where(evaluaciones.claseId.equals(claseId));

    final query = select(calificaciones)
      ..where((t) => t.evaluacionId.isInQuery(evaluacionesDeClase));

    return query.watch();
  }

  Stream<List<RubricaSeleccion>> watchRubricaEvaluacionesByClase(int claseId) {
    final evaluacionesDeClase = selectOnly(evaluaciones)
      ..addColumns([evaluaciones.id])
      ..where(evaluaciones.claseId.equals(claseId));

    final query = select(rubricaEvaluaciones)
      ..where((t) => t.evaluacionId.isInQuery(evaluacionesDeClase));

    return query.watch();
  }

  Future<void> saveCalificacion({
    int? id,
    required int alumnoId,
    required int evaluacionId,
    double? valor,
    String? evidencia,
    String? evidenciaPath,
  }) async {
    final existingQuery = select(calificaciones)
      ..where((t) =>
          t.alumnoId.equals(alumnoId) & t.evaluacionId.equals(evaluacionId));

    final existing = id != null ? null : await existingQuery.getSingleOrNull();
    final companion = CalificacionesCompanion(
      id: id != null
          ? Value(id)
          : existing != null
              ? Value(existing.id)
              : const Value.absent(),
      alumnoId: Value(alumnoId),
      evaluacionId: Value(evaluacionId),
      valor: Value(valor),
      evidencia: Value(evidencia),
      evidenciaPath: Value(evidenciaPath),
      fecha: Value(DateTime.now()),
    );

    await into(calificaciones).insertOnConflictUpdate(companion);
  }

  Future<Map<int, int>> getRubricaAssessmentSelections({
    required int alumnoId,
    required int evaluacionId,
  }) async {
    final rows = await (select(rubricaEvaluaciones)
          ..where((t) =>
              t.alumnoId.equals(alumnoId) &
              t.evaluacionId.equals(evaluacionId)))
        .get();

    return {for (final row in rows) row.criterioId: row.nivelId};
  }

  Future<double?> saveRubricaAssessment({
    required int alumnoId,
    required int evaluacionId,
    required Map<int, int?> nivelesPorCriterio,
  }) async {
    return transaction(() async {
      final evaluacion = await (select(evaluaciones)
            ..where((t) => t.id.equals(evaluacionId)))
          .getSingleOrNull();
      if (evaluacion == null || evaluacion.rubricaId == null) {
        throw ArgumentError('La evaluación indicada no usa una rúbrica.');
      }

      final criterios = await (select(criteriosRubrica)
            ..where((t) => t.rubricaId.equals(evaluacion.rubricaId!))
            ..orderBy([(t) => OrderingTerm.asc(t.orden)]))
          .get();
      if (criterios.isEmpty) {
        await saveCalificacion(
          alumnoId: alumnoId,
          evaluacionId: evaluacionId,
          valor: null,
        );
        return null;
      }

      final niveles = await (select(nivelesRubrica)
            ..where((t) => t.criterioId.isIn(criterios.map((item) => item.id))))
          .get();
      final nivelesById = {for (final nivel in niveles) nivel.id: nivel};

      await (delete(rubricaEvaluaciones)
            ..where((t) =>
                t.alumnoId.equals(alumnoId) &
                t.evaluacionId.equals(evaluacionId)))
          .go();

      var weightedTotal = 0.0;
      var weightSum = 0.0;
      var hasAnySelection = false;

      for (final criterio in criterios) {
        final nivelId = nivelesPorCriterio[criterio.id];
        if (nivelId == null) {
          continue;
        }

        final nivel = nivelesById[nivelId];
        if (nivel == null) {
          continue;
        }

        await into(rubricaEvaluaciones).insert(
          RubricaEvaluacionesCompanion.insert(
            alumnoId: alumnoId,
            evaluacionId: evaluacionId,
            criterioId: criterio.id,
            nivelId: nivel.id,
            fecha: DateTime.now(),
          ),
          mode: InsertMode.insertOrReplace,
        );

        weightedTotal += nivel.puntos * criterio.peso;
        weightSum += criterio.peso;
        hasAnySelection = true;
      }

      final valor = hasAnySelection && weightSum > 0
          ? weightedTotal / weightSum
          : null;

      await saveCalificacion(
        alumnoId: alumnoId,
        evaluacionId: evaluacionId,
        valor: valor,
      );

      return valor;
    });
  }

  Stream<CuadernoData?> watchCuadernoData(int? claseId) {
    if (claseId == null) {
      return Stream.value(null);
    }

    return Rx.combineLatest5(
      (select(clases)..where((t) => t.id.equals(claseId))).watchSingleOrNull(),
      watchAlumnosByClase(claseId),
      watchCuadernoTabsByClase(claseId),
      watchEvaluacionesByClase(claseId),
      watchCalificacionesByClase(claseId),
      (
        Clase? clase,
        List<Alumno> alumnosData,
        List<CuadernoTab> tabsData,
        List<Evaluacion> evaluacionesData,
        List<Calificacion> calificacionesData,
      ) {
        if (clase == null) {
          return null;
        }
        return CuadernoData(
          clase: clase,
          alumnos: alumnosData,
          tabs: tabsData,
          evaluaciones: evaluacionesData,
          calificaciones: calificacionesData,
        );
      },
    );
  }

  Stream<DashboardStats> watchDashboardStats() {
    return Rx.combineLatest4(
      select(alumnos).watch(),
      select(clases).watch(),
      select(evaluaciones).watch(),
      select(rubricas).watch(),
      (
        List<Alumno> alumnosData,
        List<Clase> clasesData,
        List<Evaluacion> evaluacionesData,
        List<Rubrica> rubricasData,
      ) {
        return DashboardStats(
          totalAlumnos: alumnosData.length,
          totalClases: clasesData.length,
          totalEvaluaciones: evaluacionesData.length,
          totalRubricas: rubricasData.length,
        );
      },
    );
  }

  Future<void> seedDemoDataIfEmpty() async {
    final existing = await select(alumnos).get();
    if (existing.isNotEmpty) {
      return;
    }

    await transaction(() async {
      final claseA = await saveClase(
        nombre: '2º ESO A',
        curso: 2,
        descripcion: 'Grupo de ejemplo para validación inicial.',
      );
      final claseB = await saveClase(
        nombre: '3º ESO B',
        curso: 3,
        descripcion: 'Grupo de apoyo y seguimiento.',
      );

      final alumnosIds = <int>[];
      for (final alumno in const [
        ('Ana', 'López'),
        ('Carlos', 'Ruiz'),
        ('Elena', 'Martín'),
        ('Diego', 'Santos'),
      ]) {
        alumnosIds.add(
          await saveAlumno(nombre: alumno.$1, apellidos: alumno.$2),
        );
      }

      for (final alumnoId in alumnosIds.take(3)) {
        await assignAlumnoToClase(alumnoId, claseA);
      }
      await assignAlumnoToClase(alumnosIds.last, claseB);

      final periodoId = await savePeriodo(
        nombre: '1º Trimestre',
        fechaInicio: DateTime(DateTime.now().year, 9, 10),
        fechaFin: DateTime(DateTime.now().year, 12, 20),
      );
      final unidadId = await saveUnidad(
        periodoId: periodoId,
        titulo: 'Situación de aprendizaje inicial',
        objetivos: 'Diagnosticar el punto de partida del grupo.',
        competencias: 'Competencia lingüística y aprender a aprender.',
      );
      await saveSesion(
        unidadId: unidadId,
        fecha: DateTime.now().add(const Duration(days: 2)),
        descripcion: 'Sesión de lanzamiento con dinámica de observación.',
      );

      final rubricaId = await saveRubrica(
        nombre: 'Exposición oral',
        descripcion: 'Rúbrica base para presentaciones cortas.',
      );
      final criterioId = await saveCriterio(
        rubricaId: rubricaId,
        descripcion: 'Claridad de la exposición',
        peso: 0.5,
        orden: 0,
      );
      await saveNivel(
        criterioId: criterioId,
        nivel: 'Excelente',
        puntos: 4,
        descripcion: 'Mensaje claro y estructurado.',
        orden: 0,
      );
      await saveNivel(
        criterioId: criterioId,
        nivel: 'Adecuado',
        puntos: 3,
        descripcion: 'Mensaje entendible con pequeñas lagunas.',
        orden: 1,
      );

      final evalTarea = await saveEvaluacion(
        claseId: claseA,
        nombre: 'Tarea 1',
        codigo: 'tarea_1',
        tipo: 'numerica',
        peso: 0.4,
        descripcion: 'Trabajo individual inicial.',
      );
      final evalPrueba = await saveEvaluacion(
        claseId: claseA,
        nombre: 'Prueba 1',
        codigo: 'prueba_1',
        tipo: 'numerica',
        peso: 0.6,
        descripcion: 'Prueba escrita de unidad.',
      );
      await saveEvaluacion(
        claseId: claseA,
        nombre: 'Media',
        codigo: 'media',
        tipo: 'formula',
        peso: 1,
        formula: '(tarea_1*0.4)+(prueba_1*0.6)',
        descripcion: 'Media ponderada visible en el cuaderno.',
      );

      await saveCalificacion(
        alumnoId: alumnosIds[0],
        evaluacionId: evalTarea,
        valor: 8.5,
        evidencia: 'Entrega puntual',
      );
      await saveCalificacion(
        alumnoId: alumnosIds[0],
        evaluacionId: evalPrueba,
        valor: 7.0,
      );
      await saveCalificacion(
        alumnoId: alumnosIds[1],
        evaluacionId: evalTarea,
        valor: 6.5,
      );
      await saveCalificacion(
        alumnoId: alumnosIds[1],
        evaluacionId: evalPrueba,
        valor: 7.8,
      );
    });
  }
}

class ClaseResumen {
  const ClaseResumen({
    required this.clase,
    required this.totalAlumnos,
  });

  final Clase clase;
  final int totalAlumnos;
}

class DashboardStats {
  const DashboardStats({
    required this.totalAlumnos,
    required this.totalClases,
    required this.totalEvaluaciones,
    required this.totalRubricas,
  });

  final int totalAlumnos;
  final int totalClases;
  final int totalEvaluaciones;
  final int totalRubricas;
}

class UnidadConSesiones {
  const UnidadConSesiones({
    required this.unidad,
    required this.sesiones,
  });

  final UnidadesDidactica unidad;
  final List<Sesione> sesiones;
}

class PeriodoConUnidades {
  const PeriodoConUnidades({
    required this.periodo,
    required this.unidades,
  });

  final Periodo periodo;
  final List<UnidadConSesiones> unidades;
}

class CriterioConNiveles {
  const CriterioConNiveles({
    required this.criterio,
    required this.niveles,
  });

  final CriteriosRubricaData criterio;
  final List<NivelesRubricaData> niveles;
}

class RubricaCompleta {
  const RubricaCompleta({
    required this.rubrica,
    required this.criterios,
  });

  final Rubrica rubrica;
  final List<CriterioConNiveles> criterios;
}

class CuadernoData {
  const CuadernoData({
    required this.clase,
    required this.alumnos,
    required this.tabs,
    required this.evaluaciones,
    required this.calificaciones,
  });

  final Clase clase;
  final List<Alumno> alumnos;
  final List<CuadernoTab> tabs;
  final List<Evaluacion> evaluaciones;
  final List<Calificacion> calificaciones;
}

class CuadernoCellValue {
  const CuadernoCellValue({
    required this.valor,
    required this.esFormula,
    this.calificacion,
  });

  final double? valor;
  final bool esFormula;
  final Calificacion? calificacion;
}

class CuadernoAlumnoView {
  const CuadernoAlumnoView({
    required this.alumno,
    required this.celdas,
  });

  final Alumno alumno;
  final Map<int, CuadernoCellValue> celdas;
}

class CuadernoView {
  const CuadernoView({
    required this.clase,
    required this.tabs,
    required this.evaluaciones,
    required this.filas,
  });

  final Clase clase;
  final List<CuadernoTab> tabs;
  final List<Evaluacion> evaluaciones;
  final List<CuadernoAlumnoView> filas;
}

CuadernoView buildCuadernoView(CuadernoData data) {
  final calificacionesPorAlumno = <int, List<Calificacion>>{};
  for (final calificacion in data.calificaciones) {
    calificacionesPorAlumno
        .putIfAbsent(calificacion.alumnoId, () => <Calificacion>[])
        .add(calificacion);
  }

  final filas = data.alumnos.map((alumno) {
    final propias = calificacionesPorAlumno[alumno.id] ?? <Calificacion>[];
    final porEvaluacion = {
      for (final item in propias) item.evaluacionId: item,
    };
    final valoresBase = <String, double?>{};
    final celdas = <int, CuadernoCellValue>{};

    for (final evaluacion in data.evaluaciones) {
      final key = FormulaEvaluator.normalizeIdentifier(evaluacion.codigo);
      final calificacion = porEvaluacion[evaluacion.id];
      if (evaluacion.tipo == 'formula') {
        final valorFormula =
            FormulaEvaluator.evaluate(evaluacion.formula, valoresBase);
        valoresBase[key] = valorFormula;
        celdas[evaluacion.id] = CuadernoCellValue(
          valor: valorFormula,
          esFormula: true,
        );
      } else {
        valoresBase[key] = calificacion?.valor;
        celdas[evaluacion.id] = CuadernoCellValue(
          valor: calificacion?.valor,
          esFormula: false,
          calificacion: calificacion,
        );
      }
    }

    return CuadernoAlumnoView(alumno: alumno, celdas: celdas);
  }).toList();

  return CuadernoView(
    clase: data.clase,
    tabs: data.tabs,
    evaluaciones: data.evaluaciones,
    filas: filas,
  );
}
