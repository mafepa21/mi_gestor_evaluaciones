import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/database/database.dart';
import 'package:mi_gestor_evaluaciones/providers/database_provider.dart';
import 'package:mi_gestor_evaluaciones/providers/service_providers.dart';
import 'package:mi_gestor_evaluaciones/widgets/empty_state.dart';
import 'package:mi_gestor_evaluaciones/widgets/section_card.dart';
import 'package:printing/printing.dart';

class InformesScreen extends ConsumerStatefulWidget {
  const InformesScreen({super.key});

  @override
  ConsumerState<InformesScreen> createState() => _InformesScreenState();
}

class _InformesScreenState extends ConsumerState<InformesScreen> {
  int? selectedClaseId;
  int? selectedAlumnoId;
  int? selectedRubricaId;

  @override
  Widget build(BuildContext context) {
    final clasesAsync = ref.watch(clasesProvider);
    final rubricasAsync = ref.watch(rubricasProvider);
    final cuadernoAsync = ref.watch(cuadernoViewProvider(selectedClaseId));
    final rosterAsync = selectedClaseId == null
        ? const AsyncValue.data(<Alumno>[])
        : ref.watch(alumnosDeClaseProvider(selectedClaseId!));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: ListView(
        children: [
          SectionCard(
            title: 'Centro de informes',
            subtitle: 'Generación PDF para alumno, clase y rúbrica.',
            child: Column(
              children: [
                clasesAsync.when(
                  data: (clases) {
                    if (clases.isEmpty) {
                      return const EmptyState(
                        title: 'Sin clases',
                        message: 'Necesitas clases y datos para generar informes.',
                      );
                    }

                    selectedClaseId ??= clases.first.id;

                    return DropdownButtonFormField<int>(
                      initialValue: selectedClaseId,
                      decoration: const InputDecoration(labelText: 'Clase'),
                      items: [
                        for (final clase in clases)
                          DropdownMenuItem(
                            value: clase.id,
                            child: Text('${clase.nombre} · ${clase.curso}º'),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedClaseId = value;
                          selectedAlumnoId = null;
                        });
                      },
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stack) => Text('Error: $error'),
                ),
                const SizedBox(height: 12),
                rosterAsync.when(
                  data: (alumnos) => DropdownButtonFormField<int>(
                    initialValue: selectedAlumnoId,
                    decoration: const InputDecoration(labelText: 'Alumno'),
                    items: [
                      for (final alumno in alumnos)
                        DropdownMenuItem(
                          value: alumno.id,
                          child: Text('${alumno.apellidos}, ${alumno.nombre}'),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => selectedAlumnoId = value);
                    },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stack) => Text('Error: $error'),
                ),
                const SizedBox(height: 12),
                rubricasAsync.when(
                  data: (rubricas) => DropdownButtonFormField<int>(
                    initialValue: selectedRubricaId,
                    decoration: const InputDecoration(labelText: 'Rúbrica'),
                    items: [
                      for (final rubrica in rubricas)
                        DropdownMenuItem(
                          value: rubrica.rubrica.id,
                          child: Text(rubrica.rubrica.nombre),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => selectedRubricaId = value);
                    },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stack) => Text('Error: $error'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Exportaciones disponibles',
            child: cuadernoAsync.when(
              data: (cuaderno) {
                if (cuaderno == null) {
                  return const EmptyState(
                    title: 'Selecciona una clase',
                    message: 'La exportación necesita una clase activa.',
                  );
                }

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _printClase(cuaderno),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('Resumen de clase'),
                    ),
                    OutlinedButton.icon(
                      onPressed: selectedAlumnoId == null
                          ? null
                          : () => _printAlumno(cuaderno),
                      icon: const Icon(Icons.assignment_ind_rounded),
                      label: const Text('Informe individual'),
                    ),
                    OutlinedButton.icon(
                      onPressed: selectedRubricaId == null
                          ? null
                          : () => _printRubrica(
                                rubricasAsync.value ?? const [],
                              ),
                      icon: const Icon(Icons.fact_check_rounded),
                      label: const Text('Ficha de rúbrica'),
                    ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (error, stack) => Text('Error: $error'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printClase(CuadernoView cuaderno) async {
    final report = ref.read(reportServiceProvider);
    final db = ref.read(databaseProvider);
    final clase = await (db.select(db.clases)
          ..where((tbl) => tbl.id.equals(selectedClaseId!)))
        .getSingle();

    final bytes = await report.buildClaseReport(clase: clase, cuaderno: cuaderno);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _printAlumno(CuadernoView cuaderno) async {
    final fila = cuaderno.filas.firstWhere(
      (item) => item.alumno.id == selectedAlumnoId,
    );
    final report = ref.read(reportServiceProvider);
    final bytes = await report.buildAlumnoReport(
      alumno: fila.alumno,
      evaluaciones: cuaderno.evaluaciones,
      fila: fila,
      claseNombre: cuaderno.clase.nombre,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _printRubrica(List<RubricaCompleta> rubricas) async {
    final rubrica = rubricas.firstWhere(
      (item) => item.rubrica.id == selectedRubricaId,
    );
    final bytes = await ref.read(reportServiceProvider).buildRubricaReport(
          rubrica,
        );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}
