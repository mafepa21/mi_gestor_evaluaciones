import 'package:flutter_test/flutter_test.dart';
import 'package:mi_gestor_evaluaciones/core/formula_evaluator.dart';

void main() {
  test('evalua formulas con identificadores normalizados', () {
    final result = FormulaEvaluator.evaluate(
      '(tarea_1 * 0.4) + (prueba_final * 0.6)',
      {
        'tarea_1': 8,
        'prueba_final': 6,
      },
    );

    expect(result, closeTo(6.8, 0.001));
  });

  test('devuelve null para formulas vacias', () {
    expect(FormulaEvaluator.evaluate('', const {}), isNull);
  });
}
