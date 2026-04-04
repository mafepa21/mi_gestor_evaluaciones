import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/database/database.dart';
import 'package:mi_gestor_evaluaciones/providers/database_provider.dart';
import 'package:mi_gestor_evaluaciones/services/rubric_import_service.dart';
import 'package:mi_gestor_evaluaciones/widgets/empty_state.dart';
import 'package:mi_gestor_evaluaciones/widgets/section_card.dart';

class RubricasScreen extends ConsumerStatefulWidget {
  const RubricasScreen({super.key});

  @override
  ConsumerState<RubricasScreen> createState() => _RubricasScreenState();
}

class _RubricasScreenState extends ConsumerState<RubricasScreen> {
  int? selectedRubricaId;
  _RubricaEditorDraft? _draft;
  int? _draftRubricaId;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final rubricasAsync = ref.watch(rubricasProvider);
    final clasesAsync = ref.watch(clasesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SectionCard(
              title: 'Rúbricas',
              expandChild: true,
              actions: [
                OutlinedButton.icon(
                  onPressed: () => _importRubricaDesdeExcel(context),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Importar Excel/CSV'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _createEmptyRubrica(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nueva rúbrica'),
                ),
              ],
              child: rubricasAsync.when(
                data: (rubricas) {
                  if (rubricas.isEmpty) {
                    if (_draftRubricaId == null && _draft != null) {
                      return const EmptyState(
                        title: 'Rúbrica nueva en edición',
                        message:
                            'Guárdala desde el editor de la derecha para que aparezca en la lista.',
                      );
                    }
                    return EmptyState(
                      title: 'No hay rúbricas',
                      message: 'Crea una rúbrica o impórtala desde Excel.',
                      action: FilledButton.icon(
                        onPressed: () => _createEmptyRubrica(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Crear rúbrica'),
                      ),
                    );
                  }

                  if (selectedRubricaId == null &&
                      !(_draftRubricaId == null && _draft != null)) {
                    selectedRubricaId = rubricas.first.rubrica.id;
                  }
                  final selected = rubricas.firstWhere(
                    (item) => item.rubrica.id == selectedRubricaId,
                    orElse: () => rubricas.first,
                  );
                  if (!(_draftRubricaId == null && _draft != null)) {
                    _ensureDraft(selected);
                  }

                  return ListView(
                    children: [
                      for (final rubrica in rubricas)
                        Card(
                          color: rubrica.rubrica.id == selected.rubrica.id
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            onTap: () {
                              setState(() => selectedRubricaId = rubrica.rubrica.id);
                            },
                            title: Text(rubrica.rubrica.nombre),
                            subtitle: Text(
                              '${rubrica.criterios.length} criterio(s) · '
                              '${_maxLevels(rubrica)} nivel(es)',
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: 'Duplicar',
                                  onPressed: () => _duplicateRubrica(rubrica),
                                  icon: const Icon(Icons.copy_rounded),
                                ),
                                IconButton(
                                  tooltip: 'Eliminar',
                                  onPressed: () async {
                                    await ref
                                        .read(databaseProvider)
                                        .deleteRubricaById(rubrica.rubrica.id);
                                    if (selectedRubricaId ==
                                        rubrica.rubrica.id) {
                                      setState(() {
                                        selectedRubricaId = null;
                                        _draft = null;
                                        _draftRubricaId = null;
                                      });
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Text('Error: $error'),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: SectionCard(
              title: 'Editor de rúbrica',
              expandChild: true,
              child: rubricasAsync.when(
                data: (rubricas) {
                  if (rubricas.isEmpty && !(_draftRubricaId == null && _draft != null)) {
                    return const EmptyState(
                      title: 'Sin rúbrica seleccionada',
                      message: 'Crea o importa una rúbrica para editarla.',
                    );
                  }

                  RubricaCompleta? selected;
                  if (!(_draftRubricaId == null && _draft != null)) {
                    selected = rubricas.firstWhere(
                      (item) => item.rubrica.id == selectedRubricaId,
                      orElse: () => rubricas.first,
                    );
                    _ensureDraft(selected);
                  }
                  final draft = _draft;
                  if (draft == null) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 280,
                            child: TextFormField(
                              key: ValueKey('name-${draft.id}'),
                              initialValue: draft.nombre,
                              decoration: const InputDecoration(
                                labelText: 'Nombre de la rúbrica',
                              ),
                              onChanged: (value) => draft.nombre = value,
                            ),
                          ),
                          SizedBox(
                            width: 420,
                            child: TextFormField(
                              key: ValueKey('desc-${draft.id}'),
                              initialValue: draft.descripcion,
                              decoration: const InputDecoration(
                                labelText: 'Descripción',
                              ),
                              onChanged: (value) => draft.descripcion = value,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _isSaving
                                ? null
                                : () => _saveDraft(
                                      context,
                                      original: selected,
                                    ),
                            icon: const Icon(Icons.save_rounded),
                            label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: clasesAsync.value == null || _isSaving
                                ? null
                                : () => _openAsignacionDialog(
                                      context,
                                      draft: draft,
                                      classes: clasesAsync.value!,
                                    ),
                            icon: const Icon(Icons.assignment_turned_in_rounded),
                            label: const Text('Asignar a clase/tarea'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => setState(draft.addCriterionRow),
                            icon: const Icon(Icons.playlist_add_rounded),
                            label: const Text('Añadir criterio'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => setState(draft.addLevelColumn),
                            icon: const Icon(Icons.view_column_rounded),
                            label: const Text('Añadir nivel'),
                          ),
                          Text(
                            '${draft.rows.length} criterio(s) · ${draft.levels.length} nivel(es)',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _RubricaTableEditor(
                          draft: draft,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Text('Error: $error'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _createEmptyRubrica() {
    setState(() {
      selectedRubricaId = null;
      _draftRubricaId = null;
      _draft = _RubricaEditorDraft.empty();
    });
  }

  void _ensureDraft(RubricaCompleta rubrica) {
    if (_draftRubricaId == rubrica.rubrica.id && _draft != null) {
      return;
    }

    _draftRubricaId = rubrica.rubrica.id;
    _draft = _RubricaEditorDraft.fromRubrica(rubrica);
  }

  int _maxLevels(RubricaCompleta rubrica) {
    var maxLevels = 0;
    for (final criterio in rubrica.criterios) {
      if (criterio.niveles.length > maxLevels) {
        maxLevels = criterio.niveles.length;
      }
    }
    return maxLevels;
  }

  Future<void> _duplicateRubrica(RubricaCompleta rubrica) async {
    final duplicated = _RubricaEditorDraft.fromRubrica(rubrica)
      ..id = null
      ..nombre = '${rubrica.rubrica.nombre} (copia)'
      ..clearIdentifiers();

    final rubricaId = await _persistDraft(
      duplicated,
      original: null,
    );
    if (!mounted) {
      return;
    }
    setState(() => selectedRubricaId = rubricaId);
  }

  Future<void> _importRubricaDesdeExcel(BuildContext context) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
        dialogTitle: 'Selecciona una rúbrica en formato Excel o CSV',
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }

      final file = picked.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final imported = RubricImportService.parseFile(
        bytes,
        fileName: file.name,
        fallbackTitle: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      );
      if (!context.mounted) {
        return;
      }
      final shouldCreate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importar rúbrica'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Título detectado: ${imported.title}'),
                const SizedBox(height: 8),
                Text(
                  '${imported.criteria.length} criterio(s) · ${imported.levels.length} nivel(es)',
                ),
                const SizedBox(height: 12),
                for (final level in imported.levels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('- ${level.name} (${level.points} puntos)'),
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
              child: const Text('Importar'),
            ),
          ],
        ),
      );

      if (shouldCreate != true) {
        return;
      }

      final draft = _RubricaEditorDraft.fromImported(imported);
      final rubricaId = await _persistDraft(draft, original: null);
      if (!context.mounted) {
        return;
      }
      setState(() => selectedRubricaId = rubricaId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rúbrica importada: ${imported.criteria.length} criterios y '
            '${imported.levels.length} niveles.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on PlatformException catch (error) {
      if (!context.mounted) {
        return;
      }
      final message = error.code == 'ENTITLEMENT_NOT_FOUND'
          ? 'La app macOS no tiene permiso para abrir archivos todavía. '
              'Reinicia la app tras recompilar para aplicar los nuevos permisos.'
          : 'No se pudo abrir el selector de archivos: ${error.message ?? error.code}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo importar la rúbrica: $error')),
      );
    }
  }

  Future<void> _saveDraft(
    BuildContext context, {
    required RubricaCompleta? original,
  }) async {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    if (draft.nombre.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La rúbrica necesita un nombre.')),
      );
      return;
    }
    if (draft.rows.isEmpty || draft.levels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Añade al menos un criterio y un nivel antes de guardar.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final rubricaId = await _persistDraft(draft, original: original);
      if (!context.mounted) {
        return;
      }
      setState(() {
        selectedRubricaId = rubricaId;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rúbrica guardada.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la rúbrica: $error')),
      );
    }
  }

  Future<int> _persistDraft(
    _RubricaEditorDraft draft, {
    required RubricaCompleta? original,
  }) async {
    final db = ref.read(databaseProvider);
    final rubricaId = await db.saveRubrica(
      id: draft.id,
      nombre: draft.nombre.trim(),
      descripcion: draft.descripcion.trim().isEmpty
          ? null
          : draft.descripcion.trim(),
    );

    final originalCriteriaById = <int, CriterioConNiveles>{
      for (final criterio in original?.criterios ?? const <CriterioConNiveles>[])
        criterio.criterio.id: criterio,
    };
    final keptCriteria = <int>{};

    for (var rowIndex = 0; rowIndex < draft.rows.length; rowIndex++) {
      final row = draft.rows[rowIndex];
      final criterioId = await db.saveCriterio(
        id: row.criterioId,
        rubricaId: rubricaId,
        descripcion: row.descripcion.trim().isEmpty
            ? 'Criterio ${rowIndex + 1}'
            : row.descripcion.trim(),
        peso: row.peso,
        orden: rowIndex,
      );
      keptCriteria.add(criterioId);

      final originalLevels = originalCriteriaById[row.criterioId]?.niveles ?? const [];
      final keptLevels = <int>{};

      for (var levelIndex = 0; levelIndex < draft.levels.length; levelIndex++) {
        final level = draft.levels[levelIndex];
        final cell = row.cells[levelIndex];
        final nivelId = await db.saveNivel(
          id: cell.nivelId,
          criterioId: criterioId,
          nivel: level.nombre.trim().isEmpty
              ? 'Nivel ${levelIndex + 1}'
              : level.nombre.trim(),
          puntos: level.puntos,
          descripcion: cell.descripcion.trim().isEmpty
              ? null
              : cell.descripcion.trim(),
          orden: levelIndex,
        );
        keptLevels.add(nivelId);
      }

      for (final nivel in originalLevels) {
        if (!keptLevels.contains(nivel.id)) {
          await db.deleteNivelById(nivel.id);
        }
      }
    }

    for (final criterio in original?.criterios ?? const <CriterioConNiveles>[]) {
      if (!keptCriteria.contains(criterio.criterio.id)) {
        await db.deleteCriterioById(criterio.criterio.id);
      }
    }

    return rubricaId;
  }

  Future<void> _openAsignacionDialog(
    BuildContext context, {
    required _RubricaEditorDraft draft,
    required List<Clase> classes,
  }) async {
    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Necesitas crear una clase primero.')),
      );
      return;
    }

    final taskController = TextEditingController(text: draft.nombre);
    final codeController = TextEditingController(
      text: _slugify(draft.nombre),
    );
    final pesoController = TextEditingController(text: '1');
    final descripcionController = TextEditingController(text: draft.descripcion);
    var selectedClaseId = classes.first.id;
    final db = ref.read(databaseProvider);
    List<CuadernoTab> tabs = await db.getCuadernoTabsByClaseList(selectedClaseId);
    var selectedTabId = tabs.isNotEmpty ? tabs.first.id : null;
    var createNewTab = tabs.isEmpty;
    final newTabController = TextEditingController();

    final shouldAssign = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Asignar rúbrica a clase y tarea'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Clase',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final clase in classes)
                      ChoiceChip(
                        label: Text('${clase.nombre} · ${clase.curso}º'),
                        selected: selectedClaseId == clase.id,
                        onSelected: (_) async {
                          final fetchedTabs =
                              await db.getCuadernoTabsByClaseList(clase.id);
                          if (!context.mounted) return;
                          setDialogState(() => selectedClaseId = clase.id);
                          setDialogState(() {
                            tabs = fetchedTabs;
                            selectedTabId = fetchedTabs.isNotEmpty
                                ? fetchedTabs.first.id
                                : null;
                            createNewTab = fetchedTabs.isEmpty;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: taskController,
                  decoration: const InputDecoration(
                    labelText: 'Tarea o actividad',
                  ),
                  onChanged: (value) {
                    if (codeController.text.trim().isEmpty ||
                        codeController.text == _slugify(taskController.text)) {
                      codeController.text = _slugify(value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Código del cuaderno',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pesoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Peso'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descripcionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Crear nueva pestaña'),
                  value: createNewTab,
                  onChanged: (value) {
                    setDialogState(() => createNewTab = value);
                  },
                ),
                if (!createNewTab) ...[
                  DropdownButtonFormField<int>(
                    initialValue: selectedTabId,
                    decoration: const InputDecoration(labelText: 'Pestaña'),
                    items: [
                      for (final tab in tabs)
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
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );

    if (shouldAssign != true) {
      return;
    }

    final rubricaId = draft.id ?? selectedRubricaId;
    if (rubricaId == null) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guarda la rúbrica antes de asignarla a una tarea.'),
        ),
      );
      return;
    }

    final tabId = createNewTab
        ? await db.saveCuadernoTab(
            claseId: selectedClaseId,
            nombre: newTabController.text.trim().isEmpty
                ? 'Nueva pestaña'
                : newTabController.text.trim(),
          )
        : selectedTabId ?? await db.ensureDefaultCuadernoTab(selectedClaseId);

    await db.saveEvaluacion(
          claseId: selectedClaseId,
          nombre: taskController.text.trim().isEmpty
              ? draft.nombre
              : taskController.text.trim(),
          codigo: _slugify(codeController.text.trim().isEmpty
              ? taskController.text
              : codeController.text),
          tipo: 'rubrica',
          peso: double.tryParse(pesoController.text.trim()) ?? 1,
          rubricaId: rubricaId,
          tabId: tabId,
          descripcion: descripcionController.text.trim().isEmpty
              ? null
              : descripcionController.text.trim(),
        );

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rúbrica asociada. Ya aparece en el cuaderno de la clase.'),
      ),
    );
  }

  String _slugify(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'rubrica' : normalized;
  }
}

class _RubricaTableEditor extends StatelessWidget {
  const _RubricaTableEditor({
    required this.draft,
    required this.onChanged,
  });

  final _RubricaEditorDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final columnWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(220),
      1: const FixedColumnWidth(90),
      for (var index = 0; index < draft.levels.length; index++)
        index + 2: const FixedColumnWidth(260),
    };

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            border: TableBorder.symmetric(
              inside: BorderSide(color: Theme.of(context).dividerColor),
            ),
            columnWidths: columnWidths,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                children: [
                  _TableHeaderCell(
                    child: Text(
                      'Criterio',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  _TableHeaderCell(
                    child: Text(
                      'Peso',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (var index = 0; index < draft.levels.length; index++)
                    _TableHeaderCell(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  key: ValueKey(
                                    'level-name-${draft.levels[index].id}-$index',
                                  ),
                                  initialValue: draft.levels[index].nombre,
                                  decoration: InputDecoration(
                                    labelText: 'Nivel ${index + 1}',
                                  ),
                                  onChanged: (value) {
                                    draft.levels[index].nombre = value;
                                    onChanged();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (draft.levels.length > 1)
                                IconButton(
                                  onPressed: () {
                                    draft.removeLevelColumn(index);
                                    onChanged();
                                  },
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: ValueKey(
                              'level-points-${draft.levels[index].id}-$index',
                            ),
                            initialValue: '${draft.levels[index].puntos}',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Puntos',
                            ),
                            onChanged: (value) {
                              draft.levels[index].puntos =
                                  int.tryParse(value.trim()) ??
                                      draft.levels[index].puntos;
                              onChanged();
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              for (var rowIndex = 0; rowIndex < draft.rows.length; rowIndex++)
                TableRow(
                  children: [
                    _TableBodyCell(
                      child: Column(
                        children: [
                          TextFormField(
                            key: ValueKey(
                              'criterion-${draft.rows[rowIndex].criterioId}-$rowIndex',
                            ),
                            initialValue: draft.rows[rowIndex].descripcion,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Descripción del criterio',
                            ),
                            onChanged: (value) {
                              draft.rows[rowIndex].descripcion = value;
                              onChanged();
                            },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              onPressed: draft.rows.length == 1
                                  ? null
                                  : () {
                                      draft.removeCriterionRow(rowIndex);
                                      onChanged();
                                    },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _TableBodyCell(
                      child: TextFormField(
                        key: ValueKey(
                          'weight-${draft.rows[rowIndex].criterioId}-$rowIndex',
                        ),
                        initialValue:
                            draft.rows[rowIndex].peso.toStringAsFixed(2),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Peso',
                        ),
                        onChanged: (value) {
                          draft.rows[rowIndex].peso =
                              double.tryParse(value.trim().replaceAll(',', '.')) ??
                                  draft.rows[rowIndex].peso;
                          onChanged();
                        },
                      ),
                    ),
                    for (var levelIndex = 0;
                        levelIndex < draft.levels.length;
                        levelIndex++)
                      _TableBodyCell(
                        child: TextFormField(
                          key: ValueKey(
                            'cell-${draft.rows[rowIndex].cells[levelIndex].nivelId}-$rowIndex-$levelIndex',
                          ),
                          initialValue:
                              draft.rows[rowIndex].cells[levelIndex].descripcion,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Descriptor',
                          ),
                          onChanged: (value) {
                            draft.rows[rowIndex].cells[levelIndex].descripcion =
                                value;
                            onChanged();
                          },
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

class _TableBodyCell extends StatelessWidget {
  const _TableBodyCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

class _RubricaEditorDraft {
  _RubricaEditorDraft({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.levels,
    required this.rows,
  });

  factory _RubricaEditorDraft.empty() {
    return _RubricaEditorDraft(
      id: null,
      nombre: 'Nueva rúbrica',
      descripcion: '',
      levels: [
        _RubricaDraftLevel(id: null, nombre: 'Inicial', puntos: 5),
        _RubricaDraftLevel(id: null, nombre: 'Avanzado', puntos: 10),
      ],
      rows: [
        _RubricaDraftRow(
          criterioId: null,
          descripcion: 'Nuevo criterio',
          peso: 1,
          cells: [
            _RubricaDraftCell(nivelId: null, descripcion: ''),
            _RubricaDraftCell(nivelId: null, descripcion: ''),
          ],
        ),
      ],
    );
  }

  factory _RubricaEditorDraft.fromImported(ImportedRubric imported) {
    return _RubricaEditorDraft(
      id: null,
      nombre: imported.title,
      descripcion: '',
      levels: [
        for (final level in imported.levels)
          _RubricaDraftLevel(
            id: null,
            nombre: level.name,
            puntos: level.points,
          ),
      ],
      rows: [
        for (final criterion in imported.criteria)
          _RubricaDraftRow(
            criterioId: null,
            descripcion: criterion.name,
            peso: 1,
            cells: [
              for (final cell in criterion.cells)
                _RubricaDraftCell(nivelId: null, descripcion: cell),
            ],
          ),
      ],
    );
  }

  factory _RubricaEditorDraft.fromRubrica(RubricaCompleta rubrica) {
    final maxLevels = rubrica.criterios.fold<int>(
      0,
      (maxValue, criterio) =>
          criterio.niveles.length > maxValue ? criterio.niveles.length : maxValue,
    );

    final levels = <_RubricaDraftLevel>[
      for (var index = 0; index < maxLevels; index++)
        _RubricaDraftLevel(
          id: rubrica.criterios.isNotEmpty && index < rubrica.criterios.first.niveles.length
              ? rubrica.criterios.first.niveles[index].id
              : null,
          nombre: rubrica.criterios.isNotEmpty &&
                  index < rubrica.criterios.first.niveles.length
              ? rubrica.criterios.first.niveles[index].nivel
              : 'Nivel ${index + 1}',
          puntos: rubrica.criterios.isNotEmpty &&
                  index < rubrica.criterios.first.niveles.length
              ? rubrica.criterios.first.niveles[index].puntos
              : (index + 1) * 2,
        ),
    ];

    return _RubricaEditorDraft(
      id: rubrica.rubrica.id,
      nombre: rubrica.rubrica.nombre,
      descripcion: rubrica.rubrica.descripcion ?? '',
      levels: levels,
      rows: [
        for (final criterio in rubrica.criterios)
          _RubricaDraftRow(
            criterioId: criterio.criterio.id,
            descripcion: criterio.criterio.descripcion,
            peso: criterio.criterio.peso,
            cells: [
              for (var index = 0; index < maxLevels; index++)
                _RubricaDraftCell(
                  nivelId: index < criterio.niveles.length
                      ? criterio.niveles[index].id
                      : null,
                  descripcion: index < criterio.niveles.length
                      ? criterio.niveles[index].descripcion ?? ''
                      : '',
                ),
            ],
          ),
      ],
    );
  }

  int? id;
  String nombre;
  String descripcion;
  final List<_RubricaDraftLevel> levels;
  final List<_RubricaDraftRow> rows;

  void addCriterionRow() {
    rows.add(
      _RubricaDraftRow(
        criterioId: null,
        descripcion: 'Nuevo criterio',
        peso: 1,
        cells: [
          for (var _ in levels) _RubricaDraftCell(nivelId: null, descripcion: ''),
        ],
      ),
    );
  }

  void removeCriterionRow(int index) {
    rows.removeAt(index);
  }

  void addLevelColumn() {
    levels.add(
      _RubricaDraftLevel(
        id: null,
        nombre: 'Nivel ${levels.length + 1}',
        puntos: (levels.length + 1) * 2,
      ),
    );
    for (final row in rows) {
      row.cells.add(_RubricaDraftCell(nivelId: null, descripcion: ''));
    }
  }

  void removeLevelColumn(int index) {
    levels.removeAt(index);
    for (final row in rows) {
      row.cells.removeAt(index);
    }
  }

  void clearIdentifiers() {
    for (final level in levels) {
      level.id = null;
    }
    for (final row in rows) {
      row.criterioId = null;
      for (final cell in row.cells) {
        cell.nivelId = null;
      }
    }
  }
}

class _RubricaDraftLevel {
  _RubricaDraftLevel({
    required this.id,
    required this.nombre,
    required this.puntos,
  });

  int? id;
  String nombre;
  int puntos;
}

class _RubricaDraftRow {
  _RubricaDraftRow({
    required this.criterioId,
    required this.descripcion,
    required this.peso,
    required this.cells,
  });

  int? criterioId;
  String descripcion;
  double peso;
  final List<_RubricaDraftCell> cells;
}

class _RubricaDraftCell {
  _RubricaDraftCell({
    required this.nivelId,
    required this.descripcion,
  });

  int? nivelId;
  String descripcion;
}
