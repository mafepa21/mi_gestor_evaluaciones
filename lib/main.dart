import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_gestor_evaluaciones/core/theme.dart';
import 'package:mi_gestor_evaluaciones/screens/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: MiGestorEvaluacionesApp()));
}

class MiGestorEvaluacionesApp extends StatelessWidget {
  const MiGestorEvaluacionesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiGestorEvaluaciones',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: const HomeScreen(),
    );
  }
}
