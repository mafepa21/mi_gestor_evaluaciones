import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/database/database.dart';
import 'package:mi_gestor_evaluaciones/providers/database_provider.dart';
import 'package:mi_gestor_evaluaciones/widgets/empty_state.dart';
import 'package:mi_gestor_evaluaciones/widgets/section_card.dart';
import 'package:pluto_grid/pluto_grid.dart';

class CuadernoScreen extends ConsumerStatefulWidget {
  const CuadernoScreen({super.key});

  @override
  ConsumerState<CuadernoScreen> createState() => _CuadernoScreenState();
}

class _CuadernoScreenState extends ConsumerState<CuadernoScreen> {
  int? selectedClaseId;

  @override
  Widget build(BuildContext context) {
    final clasesAsync = ref.watch(clasesProvider);
    final rubricasAsync = ref.watch(rubricasProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          SectionCard(
            title: 'Configuración del cuaderno',
            child: clasesAsync.when(
              data: (clases) {
                if (clases.isEmpty) {
                  return const EmptyState(
                    title: 'Crea una clase primero',
                    message:
                        'El cuaderno necesita al menos una clase con alumnos.',
                  );
                }

                selectedClaseId ??= clases.first.id;

                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedClaseId,
                        decoration: const InputDecoration(
                          labelText: 'Clase activa',
                        ),
                        items: [
                          for (final clase in clases)
                            DropdownMenuItem(
                              value: clase.id,
                              child: Text('${clase.nombre} · ${clase.curso}º'),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => selectedClaseId = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: selectedClaseId == null
                          ? null
                          : () => _openNuevaPestanaDialog(context),
                      icon: const Icon(Icons.tab_rounded),
                      label: const Text('Nueva pestaña'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: selectedClaseId == null
                          ? null
                          : () => _openEvaluacionDialog(
                                context,
                                rubricasAsync.value ?? const [],
                              ),
                      icon: const Icon(Icons.add_task_rounded),
                      label: const Text('Nueva evaluación'),
                    ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (error, stack) => Text('Error: $error'),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SectionCard(
              title: 'Cuaderno de calificaciones',
              subtitle:
                  'Pestañas reales, evaluación de rúbricas y edición masiva.',
              expandChild: true,
              child: _CuadernoGrid(claseId: selectedClaseId),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEvaluacionDialog(
    BuildContext context,
    List<RubricaCompleta> rubricas,
  ) async {
    if (selectedClaseId == null) {
      return;
    }

    final db = ref.read(databaseProvider);
    final existingTabs = await db.getCuadernoTabsByClaseList(selectedClaseId!);
    var selectedTabId = existingTabs.isNotEmpty ? existingTabs.first.id : null;
    var createNewTab = existingTabs.isEmpty;
    final newTabController = TextEditingController();

    final nombreController = TextEditingController();
    final codigoController = TextEditingController();
    final pesoController = TextEditingController(text: '1');
    final formulaController = TextEditingController();
    final descripcionController = TextEditingController();
    String tipo = 'numerica';
    int? rubricaId;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva evaluación'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codigoController,
                  decoration: const InputDecoration(
                    labelText: 'Código',
                    helperText: 'Ejemplo: prueba_1, media_final',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'numerica', child: Text('Numérica')),
                    DropdownMenuItem(value: 'formula', child: Text('Fórmula')),
                    DropdownMenuItem(value: 'rubrica', child: Text('Rúbrica')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => tipo = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pesoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Peso'),
                ),
                if (tipo == 'formula') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: formulaController,
                    decoration: const InputDecoration(
                      labelText: 'Fórmula',
                      helperText: 'Usa códigos como tarea_1 y prueba_1',
                    ),
                  ),
                ],
                if (tipo == 'rubrica') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: rubricaId,
                    decoration: const InputDecoration(labelText: 'Rúbrica'),
                    items: [
                      for (final rubrica in rubricas)
                        DropdownMenuItem(
                          value: rubrica.rubrica.id,
                          child: Text(rubrica.rubrica.nombre),
                        ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => rubricaId = value);
                    },
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Crear nueva pestaña'),
                  value: createNewTab,
                  onChanged: (value) {
                    setDialogState(() {
                      createNewTab = value;
                    });
                  },
                ),
                if (!createNewTab) ...[
                  DropdownButtonFormField<int>(
                    initialValue: selectedTabId,
                    decoration: const InputDecoration(labelText: 'Pestaña'),
                    items: [
                      for (final tab in existingTabs)
                        DropdownMenuItem(value: tab.id, child: Text(tab.nombre)),
                    ],
                    onChanged: (value) {
                      setDialogState(() => selectedTabId = value);
                    },
                  ),
                ] else ...[
                  TextField(
                    controller: newTabController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la nueva pestaña',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: descripcionController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (shouldSave != true) {
      return;
    }

    final tabId = createNewTab
        ? await db.saveCuadernoTab(
            claseId: selectedClaseId!,
            nombre: newTabController.text.trim().isEmpty
                ? 'Nueva pestaña'
                : newTabController.text.trim(),
          )
        : selectedTabId ?? await db.ensureDefaultCuadernoTab(selectedClaseId!);

    await db.saveEvaluacion(
      claseId: selectedClaseId!,
      nombre: nombreController.text.trim(),
      codigo: codigoController.text.trim(),
      tipo: tipo,
      peso: double.tryParse(pesoController.text.trim()) ?? 1,
      formula: tipo == 'formula' ? formulaController.text.trim() : null,
      rubricaId: tipo == 'rubrica' ? rubricaId : null,
      tabId: tabId,
      descripcion: descripcionController.text.trim().isEmpty
          ? null
          : descripcionController.text.trim(),
    );
  }

  Future<void> _openNuevaPestanaDialog(BuildContext context) async {
    if (selectedClaseId == null) return;
    final controller = TextEditingController();
    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva pestaña'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (shouldCreate != true) return;
    await ref.read(databaseProvider).saveCuadernoTab(
          claseId: selectedClaseId!,
          nombre: controller.text.trim().isEmpty
              ? 'Nueva pestaña'
              : controller.text.trim(),
        );
  }
}

class _CuadernoGrid extends ConsumerStatefulWidget {
  const _CuadernoGrid({required this.claseId});

  final int? claseId;

  @override
  ConsumerState<_CuadernoGrid> createState() => _CuadernoGridState();
}

class _CuadernoGridState extends ConsumerState<_CuadernoGrid> {
  int? _selectedTabId;

  @override
  void didUpdateWidget(covariant _CuadernoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.claseId != widget.claseId) {
      _selectedTabId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cuadernoAsync = ref.watch(cuadernoViewProvider(widget.claseId));
    final tabsAsync = ref.watch(cuadernoTabsProvider(widget.claseId));

    return cuadernoAsync.when(
      data: (cuaderno) {
        if (cuaderno == null) {
          return const EmptyState(
            title: 'Selecciona una clase',
            message: 'Elige una clase para cargar su cuaderno.',
          );
        }

        if (cuaderno.filas.isEmpty) {
          return const EmptyState(
            title: 'No hay alumnos en esta clase',
            message: 'Asigna alumnos a la clase antes de calificar.',
          );
        }

        final tabs = tabsAsync.value ?? cuaderno.tabs;
        if (tabs.isEmpty) {
          return Center(
            child: FilledButton.icon(
              onPressed: _openNuevaPestanaDialog,
              icon: const Icon(Icons.tab_rounded),
              label: const Text('Crear primera pestaña'),
            ),
          );
        }

        final selectedTabId = _selectedTabId ?? tabs.first.id;
        if (!tabs.any((tab) => tab.id == selectedTabId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedTabId = tabs.first.id);
          });
        }

        final evaluacionesVisibles = cuaderno.evaluaciones
            .where((evaluacion) => (evaluacion.tabId ?? tabs.first.id) == selectedTabId)
            .toList();

        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in tabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tab.nombre),
                        selected: tab.id == selectedTabId,
                        onSelected: (_) => setState(() => _selectedTabId = tab.id),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Nueva pestaña',
                    onPressed: _openNuevaPestanaDialog,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: evaluacionesVisibles.isEmpty
                  ? const Center(
                      child: Text('Esta pestaña no tiene columnas todavía.'),
                    )
                  : _GridView(
                      cuaderno: cuaderno,
                      evaluacionesVisibles: evaluacionesVisibles,
                      onOpenRubrica: (fila, evaluacion) => _openRubricaAssessmentView(
                        fila: fila,
                        evaluacion: evaluacion,
                        cuaderno: cuaderno,
                      ),
                      onOpenBulk: (evaluacion) => _openRubricaBulkEvaluationView(
                        evaluacion: evaluacion,
                        cuaderno: cuaderno,
                      ),
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Text('Error cargando cuaderno: $error'),
    );
  }

  Future<void> _openNuevaPestanaDialog() async {
    if (widget.claseId == null) return;
    final controller = TextEditingController();
    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva pestaña'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (shouldCreate != true) return;
    final tabId = await ref.read(databaseProvider).saveCuadernoTab(
          claseId: widget.claseId!,
          nombre:
              controller.text.trim().isEmpty ? 'Nueva pestaña' : controller.text.trim(),
        );
    if (!mounted) return;
    setState(() => _selectedTabId = tabId);
  }

  Future<void> _openRubricaAssessmentView({
    required CuadernoAlumnoView fila,
    required Evaluacion evaluacion,
    required CuadernoView cuaderno,
  }) async {
    final rubricaId = evaluacion.rubricaId;
    if (rubricaId == null) return;

    final db = ref.read(databaseProvider);
    final rubrica = await db.getRubricaCompletaById(rubricaId);
    if (rubrica == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RubricaEvaluationPage(
          db: db,
          rubrica: rubrica,
          evaluacion: evaluacion,
          alumno: fila.alumno,
          allRows: cuaderno.filas,
        ),
      ),
    );
  }

  Future<void> _openRubricaBulkEvaluationView({
    required Evaluacion evaluacion,
    required CuadernoView cuaderno,
  }) async {
    final rubricaId = evaluacion.rubricaId;
    if (rubricaId == null) return;

    final db = ref.read(databaseProvider);
    final rubrica = await db.getRubricaCompletaById(rubricaId);
    if (rubrica == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RubricaBulkEvaluationPage(
          db: db,
          rubrica: rubrica,
          evaluacion: evaluacion,
          alumnos: cuaderno.filas,
        ),
      ),
    );
  }
}

class _GridView extends ConsumerWidget {
  const _GridView({
    required this.cuaderno,
    required this.evaluacionesVisibles,
    required this.onOpenRubrica,
    required this.onOpenBulk,
  });

  final CuadernoView cuaderno;
  final List<Evaluacion> evaluacionesVisibles;
  final void Function(CuadernoAlumnoView fila, Evaluacion evaluacion) onOpenRubrica;
  final void Function(Evaluacion evaluacion) onOpenBulk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int? readAlumnoId(PlutoRow row) {
      final value = row.cells['alumno_id']?.value;
      return switch (value) {
        int id => id,
        num id => id.toInt(),
        String text => int.tryParse(text),
        _ => null,
      };
    }

    final filasByAlumnoId = <int, CuadernoAlumnoView>{
      for (final fila in cuaderno.filas) fila.alumno.id: fila,
    };

    final columns = <PlutoColumn>[
      PlutoColumn(
        title: 'AlumnoId',
        field: 'alumno_id',
        hide: true,
        readOnly: true,
        type: PlutoColumnType.number(),
      ),
      PlutoColumn(
        title: 'Alumno',
        field: 'alumno',
        width: 220,
        frozen: PlutoColumnFrozen.start,
        readOnly: true,
        type: PlutoColumnType.text(),
      ),
      for (final evaluacion in evaluacionesVisibles)
        PlutoColumn(
          title: evaluacion.codigo.toUpperCase(),
          field: 'eval_${evaluacion.id}',
          width: evaluacion.tipo == 'rubrica' ? 160 : 130,
          readOnly: evaluacion.tipo == 'formula' || evaluacion.tipo == 'rubrica',
          type: evaluacion.tipo == 'rubrica'
              ? PlutoColumnType.text()
              : PlutoColumnType.number(
                  format: '#,##0.00',
                  locale: 'es',
                ),
          renderer: evaluacion.tipo == 'rubrica'
              ? (rendererContext) => _RubricaCell(
                    value: (() {
                      final alumnoId = readAlumnoId(rendererContext.row);
                      final fila = alumnoId == null ? null : filasByAlumnoId[alumnoId];
                      return fila?.celdas[evaluacion.id]?.valor;
                    })(),
                    onTap: () {
                      final alumnoId = readAlumnoId(rendererContext.row);
                      final fila = alumnoId == null ? null : filasByAlumnoId[alumnoId];
                      if (fila == null) {
                        return;
                      }
                      onOpenRubrica(fila, evaluacion);
                    },
                  )
              : null,
          footerRenderer: (_) => Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(evaluacion.tipo, textAlign: TextAlign.center),
                if (evaluacion.tipo == 'rubrica')
                  TextButton(
                    onPressed: () => onOpenBulk(evaluacion),
                    child: const Text('Masiva'),
                  ),
              ],
            ),
          ),
        ),
    ];

    final rows = cuaderno.filas
        .map(
          (fila) => PlutoRow(
            cells: {
              'alumno_id': PlutoCell(value: fila.alumno.id),
              'alumno': PlutoCell(
                value: '${fila.alumno.apellidos}, ${fila.alumno.nombre}',
              ),
              for (final evaluacion in evaluacionesVisibles)
                'eval_${evaluacion.id}': PlutoCell(
                  value: fila.celdas[evaluacion.id]?.valor,
                ),
            },
          ),
        )
        .toList();

    return PlutoGrid(
      columns: columns,
      rows: rows,
      onLoaded: (event) {
        event.stateManager.setShowColumnFilter(true);
      },
      onChanged: (event) async {
        final field = event.column.field;
        if (!field.startsWith('eval_')) {
          return;
        }

        final evaluacionId = int.parse(field.replaceFirst('eval_', ''));
        final alumnoId = readAlumnoId(event.row);
        final fila = alumnoId == null ? null : filasByAlumnoId[alumnoId];
        if (fila == null) {
          return;
        }
        final evaluacion = evaluacionesVisibles.firstWhere(
          (item) => item.id == evaluacionId,
        );
        if (evaluacion.tipo == 'formula' || evaluacion.tipo == 'rubrica') {
          return;
        }

        final parsed = switch (event.value) {
          num number => number.toDouble(),
          String text => double.tryParse(text.replaceAll(',', '.')),
          _ => null,
        };

        await ref.read(databaseProvider).saveCalificacion(
              id: fila.celdas[evaluacionId]?.calificacion?.id,
              alumnoId: fila.alumno.id,
              evaluacionId: evaluacionId,
              valor: parsed,
              evidencia: fila.celdas[evaluacionId]?.calificacion?.evidencia,
              evidenciaPath: fila.celdas[evaluacionId]?.calificacion?.evidenciaPath,
            );
      },
      configuration: PlutoGridConfiguration(
        style: PlutoGridStyleConfig(
          rowHeight: 52,
          cellTextStyle: Theme.of(context).textTheme.bodyMedium!,
          columnTextStyle: Theme.of(context).textTheme.titleSmall!,
        ),
      ),
    );
  }
}

class _RubricaEvaluationPage extends StatefulWidget {
  const _RubricaEvaluationPage({
    required this.db,
    required this.rubrica,
    required this.evaluacion,
    required this.alumno,
    required this.allRows,
  });

  final AppDatabase db;
  final RubricaCompleta rubrica;
  final Evaluacion evaluacion;
  final Alumno alumno;
  final List<CuadernoAlumnoView> allRows;

  @override
  State<_RubricaEvaluationPage> createState() => _RubricaEvaluationPageState();
}

class _RubricaEvaluationPageState extends State<_RubricaEvaluationPage> {
  final Map<int, int?> _selections = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final initialSelections = await widget.db.getRubricaAssessmentSelections(
      alumnoId: widget.alumno.id,
      evaluacionId: widget.evaluacion.id,
    );
    if (!mounted) return;
    setState(() {
      _selections
        ..clear()
        ..addAll(initialSelections);
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.db.saveRubricaAssessment(
      alumnoId: widget.alumno.id,
      evaluacionId: widget.evaluacion.id,
      nivelesPorCriterio: _selections,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final score = _computeRubricaScore(widget.rubrica, _selections);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.evaluacion.nombre} · ${widget.alumno.nombre}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _RubricaBulkEvaluationPage(
                    db: widget.db,
                    rubrica: widget.rubrica,
                    evaluacion: widget.evaluacion,
                    alumnos: widget.allRows,
                  ),
                ),
              );
            },
            child: const Text('Vista masiva'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.rubrica.rubrica.nombre,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Nota actual: ${_formatScore(score)}'),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final criterio in widget.rubrica.criterios)
                          Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    criterio.criterio.descripcion,
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ChoiceChip(
                                        label: const Text('Sin valorar'),
                                        selected: _selections[criterio.criterio.id] == null,
                                        onSelected: (_) {
                                          setState(() {
                                            _selections[criterio.criterio.id] = null;
                                          });
                                        },
                                      ),
                                      for (final nivel in criterio.niveles)
                                        ChoiceChip(
                                          label: Text('${nivel.nivel} (${nivel.puntos})'),
                                          selected:
                                              _selections[criterio.criterio.id] == nivel.id,
                                          onSelected: (_) {
                                            setState(() {
                                              _selections[criterio.criterio.id] = nivel.id;
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_rounded),
          label: Text(_saving ? 'Guardando...' : 'Guardar evaluación'),
        ),
      ),
    );
  }
}

class _RubricaBulkEvaluationPage extends StatefulWidget {
  const _RubricaBulkEvaluationPage({
    required this.db,
    required this.rubrica,
    required this.evaluacion,
    required this.alumnos,
  });

  final AppDatabase db;
  final RubricaCompleta rubrica;
  final Evaluacion evaluacion;
  final List<CuadernoAlumnoView> alumnos;

  @override
  State<_RubricaBulkEvaluationPage> createState() => _RubricaBulkEvaluationPageState();
}

class _RubricaBulkEvaluationPageState extends State<_RubricaBulkEvaluationPage> {
  final Map<int, Map<int, int?>> _byStudentSelections = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final fila in widget.alumnos) {
      final selections = await widget.db.getRubricaAssessmentSelections(
        alumnoId: fila.alumno.id,
        evaluacionId: widget.evaluacion.id,
      );
      _byStudentSelections[fila.alumno.id] = {
        for (final criterio in widget.rubrica.criterios)
          criterio.criterio.id: selections[criterio.criterio.id],
      };
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);

    for (final fila in widget.alumnos) {
      await widget.db.saveRubricaAssessment(
        alumnoId: fila.alumno.id,
        evaluacionId: widget.evaluacion.id,
        nivelesPorCriterio: _byStudentSelections[fila.alumno.id] ?? const <int, int?>{},
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Evaluación masiva · ${widget.evaluacion.nombre}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.alumnos.length,
              itemBuilder: (context, index) {
                final fila = widget.alumnos[index];
                final studentSelections =
                    _byStudentSelections[fila.alumno.id] ?? <int, int?>{};
                final score = _computeRubricaScore(widget.rubrica, studentSelections);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${fila.alumno.apellidos}, ${fila.alumno.nombre}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('Nota: ${_formatScore(score)}'),
                        const SizedBox(height: 12),
                        for (final criterio in widget.rubrica.criterios) ...[
                          Text(criterio.criterio.descripcion),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Sin valorar'),
                                selected: studentSelections[criterio.criterio.id] == null,
                                onSelected: (_) {
                                  setState(() {
                                    studentSelections[criterio.criterio.id] = null;
                                  });
                                },
                              ),
                              for (final nivel in criterio.niveles)
                                ChoiceChip(
                                  label: Text('${nivel.nivel} (${nivel.puntos})'),
                                  selected:
                                      studentSelections[criterio.criterio.id] == nivel.id,
                                  onSelected: (_) {
                                    setState(() {
                                      studentSelections[criterio.criterio.id] = nivel.id;
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _saveAll,
          icon: const Icon(Icons.save_rounded),
          label: Text(_saving ? 'Guardando...' : 'Guardar evaluación masiva'),
        ),
      ),
    );
  }
}

double? _computeRubricaScore(RubricaCompleta rubrica, Map<int, int?> selections) {
  if (rubrica.criterios.isEmpty) return null;

  final levelsById = <int, NivelesRubricaData>{
    for (final criterio in rubrica.criterios)
      for (final nivel in criterio.niveles) nivel.id: nivel,
  };

  var weightedTotal = 0.0;
  var weightSum = 0.0;
  var hasSelection = false;

  for (final criterio in rubrica.criterios) {
    final nivelId = selections[criterio.criterio.id];
    if (nivelId == null) continue;
    final nivel = levelsById[nivelId];
    if (nivel == null) continue;

    weightedTotal += nivel.puntos * criterio.criterio.peso;
    weightSum += criterio.criterio.peso;
    hasSelection = true;
  }

  if (!hasSelection || weightSum <= 0) return null;
  return weightedTotal / weightSum;
}

String _formatScore(double? value) {
  if (value == null) return 'Sin evaluar';
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

class _RubricaCell extends StatelessWidget {
  const _RubricaCell({
    required this.value,
    required this.onTap,
  });

  final double? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = value == null
        ? 'Evaluar'
        : value!.toStringAsFixed(2).replaceAll('.', ',');

    return Center(
      child: OutlinedButton(
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
