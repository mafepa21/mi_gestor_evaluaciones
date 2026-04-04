import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/database/database.dart';
import 'package:mi_gestor_evaluaciones/providers/database_provider.dart';
import 'package:mi_gestor_evaluaciones/widgets/empty_state.dart';
import 'package:mi_gestor_evaluaciones/widgets/section_card.dart';

class AlumnosScreen extends ConsumerWidget {
  const AlumnosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alumnosAsync = ref.watch(alumnosProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAlumnoDialog(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo alumno'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: SectionCard(
          title: 'Gestión de alumnos',
          subtitle: 'CRUD básico con persistencia local en Drift.',
          child: alumnosAsync.when(
            data: (alumnos) {
              if (alumnos.isEmpty) {
                return EmptyState(
                  title: 'No hay alumnos todavía',
                  message: 'Empieza creando tu primer alumno.',
                  action: FilledButton.icon(
                    onPressed: () => _openAlumnoDialog(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear alumno'),
                  ),
                );
              }

              return Column(
                children: [
                  for (final alumno in alumnos)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(alumno.nombre.characters.first),
                        ),
                        title: Text('${alumno.nombre} ${alumno.apellidos}'),
                        subtitle: Text(
                          alumno.email?.isNotEmpty == true
                              ? alumno.email!
                              : 'Sin email registrado',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              onPressed: () =>
                                  _openAlumnoDialog(context, ref, alumno: alumno),
                              icon: const Icon(Icons.edit_rounded),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _confirmDelete(context, ref, alumno: alumno),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Text('Error cargando alumnos: $error'),
          ),
        ),
      ),
    );
  }

  Future<void> _openAlumnoDialog(
    BuildContext context,
    WidgetRef ref, {
    Alumno? alumno,
  }) async {
    final nombreController = TextEditingController(text: alumno?.nombre ?? '');
    final apellidosController =
        TextEditingController(text: alumno?.apellidos ?? '');
    final emailController = TextEditingController(text: alumno?.email ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(alumno == null ? 'Nuevo alumno' : 'Editar alumno'),
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
                controller: apellidosController,
                decoration: const InputDecoration(labelText: 'Apellidos'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
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

    if (saved != true) {
      return;
    }

    await ref.read(databaseProvider).saveAlumno(
          id: alumno?.id,
          nombre: nombreController.text.trim(),
          apellidos: apellidosController.text.trim(),
          email: emailController.text.trim().isEmpty
              ? null
              : emailController.text.trim(),
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref, {
    required Alumno alumno,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar alumno'),
        content: Text(
          'Se eliminará a ${alumno.nombre} ${alumno.apellidos} y sus relaciones asociadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(databaseProvider).deleteAlumnoById(alumno.id);
    }
  }
}
