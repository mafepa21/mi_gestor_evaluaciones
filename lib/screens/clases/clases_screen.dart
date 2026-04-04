import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/database/database.dart';
import 'package:mi_gestor_evaluaciones/providers/database_provider.dart';
import 'package:mi_gestor_evaluaciones/services/student_import_service.dart';
import 'package:mi_gestor_evaluaciones/widgets/empty_state.dart';
import 'package:mi_gestor_evaluaciones/widgets/section_card.dart';

class ClasesScreen extends ConsumerStatefulWidget {
  const ClasesScreen({super.key});

  @override
  ConsumerState<ClasesScreen> createState() => _ClasesScreenState();
}

class _ClasesScreenState extends ConsumerState<ClasesScreen> {
  int? selectedClaseId;

  @override
  Widget build(BuildContext context) {
    final clasesAsync = ref.watch(clasesResumenProvider);
    final alumnosAsync = ref.watch(alumnosProvider);
    final rosterAsync = selectedClaseId == null
        ? const AsyncValue.data(<Alumno>[])
        : ref.watch(alumnosDeClaseProvider(selectedClaseId!));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SectionCard(
              title: 'Clases',
              expandChild: true,
              actions: [
                FilledButton.icon(
                  onPressed: () => _openClaseDialog(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nueva clase'),
                ),
              ],
              child: clasesAsync.when(
                data: (clases) {
                  if (clases.isEmpty) {
                    return const EmptyState(
                      title: 'No hay clases',
                      message: 'Crea una clase para empezar a organizar alumnos.',
                    );
                  }

                  if (selectedClaseId == null ||
                      clases.every((item) => item.clase.id != selectedClaseId)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => selectedClaseId = clases.first.clase.id);
                      }
                    });
                  }

                  return ListView(
                    children: [
                      for (final item in clases)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          color: selectedClaseId == item.clase.id
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: ListTile(
                            onTap: () {
                              setState(() => selectedClaseId = item.clase.id);
                            },
                            title: Text(item.clase.nombre),
                            subtitle: Text(
                              'Curso ${item.clase.curso} · ${item.totalAlumnos} alumno(s)',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await _openClaseDialog(
                                    context,
                                    clase: item.clase,
                                  );
                                }
                                if (value == 'delete') {
                                  await ref
                                      .read(databaseProvider)
                                      .deleteClaseById(item.clase.id);
                                  if (selectedClaseId == item.clase.id) {
                                    setState(() => selectedClaseId = null);
                                  }
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Eliminar'),
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
            child: SectionCard(
              title: 'Asignación de alumnos',
              expandChild: true,
              subtitle: selectedClaseId == null
                  ? 'Selecciona una clase.'
                  : 'Alta y baja de alumnos en la clase seleccionada.',
              actions: [
                OutlinedButton.icon(
                  onPressed: selectedClaseId == null
                      ? null
                      : () => _importAlumnosDesdeExcel(
                            context,
                            clasesAsync.value ?? const [],
                          ),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Importar Excel'),
                ),
              ],
              child: Column(
                children: [
                  alumnosAsync.when(
                    data: (alumnos) => _AssignmentBar(
                      enabled: selectedClaseId != null,
                      alumnos: alumnos,
                      onAssign: (alumnoId) async {
                        if (selectedClaseId == null) {
                          return;
                        }
                        await ref
                            .read(databaseProvider)
                            .assignAlumnoToClase(alumnoId, selectedClaseId!);
                      },
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stack) => Text('Error: $error'),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: rosterAsync.when(
                      data: (roster) {
                        if (selectedClaseId == null) {
                          return const EmptyState(
                            title: 'Sin clase seleccionada',
                            message: 'Elige una clase para gestionar su lista.',
                          );
                        }
                        if (roster.isEmpty) {
                          return const EmptyState(
                            title: 'Clase vacía',
                            message: 'Asigna alumnos desde el selector superior.',
                          );
                        }
                        return ListView(
                          children: [
                            for (final alumno in roster)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.person_rounded),
                                title:
                                    Text('${alumno.nombre} ${alumno.apellidos}'),
                                subtitle: Text(alumno.email ?? 'Sin email'),
                                trailing: IconButton(
                                  onPressed: () => ref
                                      .read(databaseProvider)
                                      .removeAlumnoFromClase(
                                        alumno.id,
                                        selectedClaseId!,
                                      ),
                                  icon: const Icon(Icons.person_remove_rounded),
                                ),
                              ),
                          ],
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stack) => Text('Error: $error'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openClaseDialog(BuildContext context, {Clase? clase}) async {
    final nombreController = TextEditingController(text: clase?.nombre ?? '');
    final cursoController =
        TextEditingController(text: clase?.curso.toString() ?? '1');
    final descripcionController =
        TextEditingController(text: clase?.descripcion ?? '');

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(clase == null ? 'Nueva clase' : 'Editar clase'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cursoController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Curso'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descripcionController,
                maxLines: 3,
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
    );

    if (shouldSave != true) {
      return;
    }

    final id = await ref.read(databaseProvider).saveClase(
          id: clase?.id,
          nombre: nombreController.text.trim(),
          curso: int.tryParse(cursoController.text.trim()) ?? 1,
          descripcion: descripcionController.text.trim().isEmpty
              ? null
              : descripcionController.text.trim(),
        );

    if (mounted) {
      setState(() => selectedClaseId = id);
    }
  }

  Future<void> _importAlumnosDesdeExcel(
    BuildContext context,
    List<ClaseResumen> clases,
  ) async {
    if (selectedClaseId == null) {
      return;
    }

    final selectedClase = clases
        .map((item) => item.clase)
        .cast<Clase?>()
        .firstWhere((item) => item?.id == selectedClaseId, orElse: () => null);

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
      dialogTitle: 'Selecciona un listado de alumnos en formato Excel',
    );

    if (picked == null || picked.files.isEmpty) {
      return;
    }

    try {
      final file = picked.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final sheet = StudentImportService.parseXlsx(bytes);
      if (!context.mounted) {
        return;
      }
      final shouldImport = await _confirmStudentImport(
        context,
        sheet: sheet,
        selectedClase: selectedClase,
      );

      if (shouldImport != true) {
        return;
      }

      final db = ref.read(databaseProvider);
      final allStudents = await db.getAlumnosList();
      final roster = await db.getAlumnosByClaseList(selectedClaseId!);
      final studentIdsByKey = <String, int>{
        for (final alumno in allStudents) _studentKey(alumno): alumno.id,
      };
      final rosterKeys = roster.map(_studentKey).toSet();
      var createdCount = 0;
      var linkedCount = 0;
      var skippedCount = 0;

      await db.transaction(() async {
        for (final student in sheet.students) {
          final key = _studentKeyFromNames(student.nombre, student.apellidos);
          if (rosterKeys.contains(key)) {
            skippedCount++;
            continue;
          }

          var alumnoId = studentIdsByKey[key];
          if (alumnoId == null) {
            alumnoId = await db.saveAlumno(
              nombre: student.nombre,
              apellidos: student.apellidos,
            );
            studentIdsByKey[key] = alumnoId;
            createdCount++;
          }

          await db.assignAlumnoToClase(alumnoId, selectedClaseId!);
          rosterKeys.add(key);
          linkedCount++;
        }
      });

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importación completada: $linkedCount asignados, '
            '$createdCount nuevos y $skippedCount omitidos.',
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
        SnackBar(content: Text('No se pudo importar el archivo: $error')),
      );
    }
  }

  Future<bool?> _confirmStudentImport(
    BuildContext context, {
    required StudentImportSheet sheet,
    required Clase? selectedClase,
  }) {
    final selectedClaseLabel = selectedClase == null
        ? 'Clase actual'
        : '${selectedClase.nombre} · Curso ${selectedClase.curso}';

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar alumnos desde Excel'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Clase de destino: $selectedClaseLabel'),
              if (sheet.classLabel != null) ...[
                const SizedBox(height: 8),
                Text('Clase detectada en el archivo: ${sheet.classLabel}'),
              ],
              if (sheet.subject != null) ...[
                const SizedBox(height: 8),
                Text('Materia: ${sheet.subject}'),
              ],
              if (sheet.schoolYear != null) ...[
                const SizedBox(height: 8),
                Text('Curso escolar: ${sheet.schoolYear}'),
              ],
              const SizedBox(height: 12),
              Text('Se han detectado ${sheet.students.length} alumno(s).'),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final student in sheet.students.take(12))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('- ${student.fullName}'),
                        ),
                      if (sheet.students.length > 12)
                        Text(
                          '...y ${sheet.students.length - 12} más.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
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
  }

  String _studentKey(Alumno alumno) {
    return _studentKeyFromNames(alumno.nombre, alumno.apellidos);
  }

  String _studentKeyFromNames(String nombre, String apellidos) {
    return '$nombre $apellidos'
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _AssignmentBar extends StatefulWidget {
  const _AssignmentBar({
    required this.enabled,
    required this.alumnos,
    required this.onAssign,
  });

  final bool enabled;
  final List<Alumno> alumnos;
  final Future<void> Function(int alumnoId) onAssign;

  @override
  State<_AssignmentBar> createState() => _AssignmentBarState();
}

class _AssignmentBarState extends State<_AssignmentBar> {
  int? alumnoId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: alumnoId,
            decoration: const InputDecoration(
              labelText: 'Añadir alumno a la clase',
            ),
            items: [
              for (final alumno in widget.alumnos)
                DropdownMenuItem(
                  value: alumno.id,
                  child: Text('${alumno.apellidos}, ${alumno.nombre}'),
                ),
            ],
            onChanged: widget.enabled
                ? (value) => setState(() => alumnoId = value)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: !widget.enabled || alumnoId == null
              ? null
              : () async {
                  await widget.onAssign(alumnoId!);
                  if (mounted) {
                    setState(() => alumnoId = null);
                  }
                },
          child: const Text('Asignar'),
        ),
      ],
    );
  }
}
