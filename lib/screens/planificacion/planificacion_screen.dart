import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/core/date_utils.dart';
import 'package:mi_gestor_evaluaciones/database/database.dart';
import 'package:mi_gestor_evaluaciones/providers/database_provider.dart';
import 'package:mi_gestor_evaluaciones/widgets/empty_state.dart';
import 'package:mi_gestor_evaluaciones/widgets/section_card.dart';
import 'package:table_calendar/table_calendar.dart';

class PlanificacionScreen extends ConsumerStatefulWidget {
  const PlanificacionScreen({super.key});

  @override
  ConsumerState<PlanificacionScreen> createState() =>
      _PlanificacionScreenState();
}

class _PlanificacionScreenState extends ConsumerState<PlanificacionScreen> {
  DateTime selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final planificacionAsync = ref.watch(planificacionProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          SectionCard(
            title: 'Calendario didáctico',
            actions: [
              FilledButton.icon(
                onPressed: () => _openPeriodoDialog(context),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('Nuevo periodo'),
              ),
            ],
            child: planificacionAsync.when(
              data: (periodos) {
                final sesiones = periodos
                    .expand((periodo) => periodo.unidades)
                    .expand((unidad) => unidad.sesiones)
                    .toList();

                return TableCalendar<Sesione>(
                  firstDay: DateTime(DateTime.now().year - 1),
                  lastDay: DateTime(DateTime.now().year + 2),
                  focusedDay: selectedDay,
                  selectedDayPredicate: (day) => isSameDay(day, selectedDay),
                  eventLoader: (day) => sesiones
                      .where(
                        (sesion) => isSameDay(day, sesion.fecha),
                      )
                      .toList(),
                  onDaySelected: (selected, focused) {
                    setState(() => selectedDay = selected);
                  },
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (error, stack) => Text('Error: $error'),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: planificacionAsync.when(
              data: (periodos) {
                if (periodos.isEmpty) {
                  return const EmptyState(
                    title: 'Sin periodos definidos',
                    message:
                        'Crea un periodo para empezar a organizar unidades y sesiones.',
                  );
                }

                return ListView(
                  children: [
                    for (final periodo in periodos)
                      SectionCard(
                        title: periodo.periodo.nombre,
                        subtitle:
                            '${formatDate(periodo.periodo.fechaInicio)} - ${formatDate(periodo.periodo.fechaFin)}',
                        actions: [
                          IconButton(
                            onPressed: () => _openUnidadDialog(
                              context,
                              periodoId: periodo.periodo.id,
                            ),
                            icon: const Icon(Icons.add_rounded),
                          ),
                          IconButton(
                            onPressed: () => ref
                                .read(databaseProvider)
                                .deletePeriodoById(periodo.periodo.id),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                        child: periodo.unidades.isEmpty
                            ? const Text('No hay unidades didácticas todavía.')
                            : Column(
                                children: [
                                  for (final unidad in periodo.unidades)
                                    ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      title: Text(unidad.unidad.titulo),
                                      subtitle: Text(
                                        unidad.unidad.competencias,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Wrap(
                                        spacing: 8,
                                        children: [
                                          IconButton(
                                            onPressed: () => _openSesionDialog(
                                              context,
                                              unidadId: unidad.unidad.id,
                                            ),
                                            icon:
                                                const Icon(Icons.event_note_rounded),
                                          ),
                                          IconButton(
                                            onPressed: () => ref
                                                .read(databaseProvider)
                                                .deleteUnidadById(
                                                  unidad.unidad.id,
                                                ),
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                            ),
                                          ),
                                        ],
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Objetivos: ${unidad.unidad.objetivos}',
                                            ),
                                          ),
                                        ),
                                        if (unidad.sesiones.isEmpty)
                                          const Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text('Sin sesiones todavía.'),
                                          ),
                                        for (final sesion in unidad.sesiones)
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading:
                                                const Icon(Icons.event_rounded),
                                            title: Text(sesion.descripcion),
                                            subtitle:
                                                Text(formatDateTime(sesion.fecha)),
                                            trailing: IconButton(
                                              onPressed: () => ref
                                                  .read(databaseProvider)
                                                  .deleteSesionById(sesion.id),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Text('Error: $error'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPeriodoDialog(BuildContext context) async {
    final nombreController = TextEditingController();
    DateTime inicio = DateTime.now();
    DateTime fin = DateTime.now().add(const Duration(days: 90));

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuevo periodo'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 12),
                _DatePickerRow(
                  label: 'Inicio',
                  value: inicio,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      initialDate: inicio,
                    );
                    if (picked != null) {
                      setDialogState(() => inicio = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _DatePickerRow(
                  label: 'Fin',
                  value: fin,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      initialDate: fin,
                    );
                    if (picked != null) {
                      setDialogState(() => fin = picked);
                    }
                  },
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

    if (shouldSave == true) {
      await ref.read(databaseProvider).savePeriodo(
            nombre: nombreController.text.trim(),
            fechaInicio: inicio,
            fechaFin: fin,
          );
    }
  }

  Future<void> _openUnidadDialog(
    BuildContext context, {
    required int periodoId,
  }) async {
    final tituloController = TextEditingController();
    final objetivosController = TextEditingController();
    final competenciasController = TextEditingController();

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva unidad'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tituloController,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: objetivosController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Objetivos'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: competenciasController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Competencias'),
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

    if (shouldSave == true) {
      await ref.read(databaseProvider).saveUnidad(
            periodoId: periodoId,
            titulo: tituloController.text.trim(),
            objetivos: objetivosController.text.trim(),
            competencias: competenciasController.text.trim(),
          );
    }
  }

  Future<void> _openSesionDialog(
    BuildContext context, {
    required int unidadId,
  }) async {
    final descripcionController = TextEditingController();
    DateTime fecha = DateTime.now();

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva sesión'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: descripcionController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                _DatePickerRow(
                  label: 'Fecha',
                  value: fecha,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      initialDate: fecha,
                    );
                    if (picked != null) {
                      setDialogState(() => fecha = picked);
                    }
                  },
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

    if (shouldSave == true) {
      await ref.read(databaseProvider).saveSesion(
            unidadId: unidadId,
            fecha: fecha,
            descripcion: descripcionController.text.trim(),
          );
    }
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(formatDate(value)),
      ),
    );
  }
}
