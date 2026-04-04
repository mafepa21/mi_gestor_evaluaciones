import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/core/date_utils.dart';
import 'package:mi_gestor_evaluaciones/providers/database_provider.dart';
import 'package:mi_gestor_evaluaciones/providers/service_providers.dart';
import 'package:mi_gestor_evaluaciones/screens/alumnos/alumnos_screen.dart';
import 'package:mi_gestor_evaluaciones/screens/clases/clases_screen.dart';
import 'package:mi_gestor_evaluaciones/screens/evaluaciones/cuaderno_screen.dart';
import 'package:mi_gestor_evaluaciones/screens/informes/informes_screen.dart';
import 'package:mi_gestor_evaluaciones/screens/planificacion/planificacion_screen.dart';
import 'package:mi_gestor_evaluaciones/screens/rubricas/rubricas_screen.dart';
import 'package:mi_gestor_evaluaciones/widgets/empty_state.dart';
import 'package:mi_gestor_evaluaciones/widgets/section_card.dart';

enum _HomeSection {
  inicio('Inicio', Icons.home_rounded),
  alumnos('Alumnos', Icons.people_alt_rounded),
  clases('Clases', Icons.class_rounded),
  cuaderno('Cuaderno', Icons.grid_view_rounded),
  planificacion('Planificación', Icons.calendar_month_rounded),
  rubricas('Rúbricas', Icons.rule_folder_rounded),
  informes('Informes', Icons.picture_as_pdf_rounded);

  const _HomeSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _HomeSection section = _HomeSection.inicio;
  bool isBusy = false;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 1080;
    final content = _buildBody();

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isWide)
              NavigationRail(
                selectedIndex: _HomeSection.values.indexOf(section),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.school_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('MiGestor'),
                    ],
                  ),
                ),
                destinations: [
                  for (final item in _HomeSection.values)
                    NavigationRailDestination(
                      icon: Icon(item.icon),
                      label: Text(item.label),
                    ),
                ],
                onDestinationSelected: (index) {
                  setState(() => section = _HomeSection.values[index]);
                },
              ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                section.label,
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                              Text(
                                'Producto local-first para evaluación, planificación y generación de informes.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: isBusy ? null : _seedDemoData,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('Cargar demo'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: isBusy ? null : _createBackup,
                          icon: const Icon(Icons.backup_rounded),
                          label: const Text('Crear backup'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _HomeSection.values.indexOf(section),
              onDestinationSelected: (index) {
                setState(() => section = _HomeSection.values[index]);
              },
              destinations: [
                for (final item in _HomeSection.values)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    label: item.label,
                  ),
              ],
            ),
    );
  }

  Widget _buildBody() {
    return switch (section) {
      _HomeSection.inicio => const _DashboardView(),
      _HomeSection.alumnos => const AlumnosScreen(),
      _HomeSection.clases => const ClasesScreen(),
      _HomeSection.cuaderno => const CuadernoScreen(),
      _HomeSection.planificacion => const PlanificacionScreen(),
      _HomeSection.rubricas => const RubricasScreen(),
      _HomeSection.informes => const InformesScreen(),
    };
  }

  Future<void> _seedDemoData() async {
    setState(() => isBusy = true);
    try {
      await ref.read(demoSeedProvider).seedIfEmpty();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos demo cargados o ya disponibles.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isBusy = false);
      }
    }
  }

  Future<void> _createBackup() async {
    setState(() => isBusy = true);
    try {
      final path = await ref.read(backupServiceProvider).createBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup creado en $path')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear el backup: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isBusy = false);
      }
    }
  }
}

class _DashboardView extends ConsumerWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final clasesAsync = ref.watch(clasesResumenProvider);
    final planificacionAsync = ref.watch(planificacionProvider);
    final rubricasAsync = ref.watch(rubricasProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        statsAsync.when(
          data: (stats) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatCard(title: 'Alumnos', value: '${stats.totalAlumnos}'),
              _StatCard(title: 'Clases', value: '${stats.totalClases}'),
              _StatCard(
                title: 'Evaluaciones',
                value: '${stats.totalEvaluaciones}',
              ),
              _StatCard(title: 'Rúbricas', value: '${stats.totalRubricas}'),
            ],
          ),
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => Text('Error cargando métricas: $error'),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Clases activas',
          subtitle: 'Resumen rápido del estado del curso.',
          child: clasesAsync.when(
            data: (clases) {
              if (clases.isEmpty) {
                return const EmptyState(
                  title: 'Todavía no hay clases',
                  message: 'Crea una clase y asigna alumnos para empezar.',
                );
              }
              return Column(
                children: [
                  for (final clase in clases)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text('${clase.clase.curso}º'),
                      ),
                      title: Text(clase.clase.nombre),
                      subtitle:
                          Text('${clase.totalAlumnos} alumno(s) asignados'),
                    ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => Text('Error: $error'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SectionCard(
                title: 'Próximas sesiones',
                child: planificacionAsync.when(
                  data: (periodos) {
                    final sesiones = periodos
                        .expand((periodo) => periodo.unidades)
                        .expand((unidad) => unidad.sesiones)
                        .where(
                          (sesion) => sesion.fecha.isAfter(
                            DateTime.now().subtract(const Duration(days: 1)),
                          ),
                        )
                        .toList()
                      ..sort((a, b) => a.fecha.compareTo(b.fecha));

                    if (sesiones.isEmpty) {
                      return const EmptyState(
                        title: 'Sin sesiones previstas',
                        message:
                            'Añade sesiones en planificación para verlas aquí.',
                      );
                    }

                    return Column(
                      children: [
                        for (final sesion in sesiones.take(5))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event_available_rounded),
                            title: Text(sesion.descripcion),
                            subtitle: Text(formatDateTime(sesion.fecha)),
                          ),
                      ],
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stack) => Text('Error: $error'),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SectionCard(
                title: 'Rúbricas disponibles',
                child: rubricasAsync.when(
                  data: (rubricas) {
                    if (rubricas.isEmpty) {
                      return const EmptyState(
                        title: 'Sin rúbricas',
                        message:
                            'Crea al menos una rúbrica para reutilizarla en evaluaciones.',
                      );
                    }

                    return Column(
                      children: [
                        for (final rubrica in rubricas.take(5))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.rule_rounded),
                            title: Text(rubrica.rubrica.nombre),
                            subtitle: Text(
                              '${rubrica.criterios.length} criterio(s)',
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stack) => Text('Error: $error'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
