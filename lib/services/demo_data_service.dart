import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/providers/database_provider.dart';

final demoDataServiceProvider = Provider<DemoDataService>((ref) {
  return DemoDataService(ref);
});

class DemoDataService {
  const DemoDataService(this.ref);

  final Ref ref;

  Future<void> seedIfEmpty() {
    return ref.read(databaseProvider).seedDemoDataIfEmpty();
  }
}
