import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:mi_gestor_evaluaciones/database/database.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportService {
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final NumberFormat _numberFormat = NumberFormat('0.00');

  Future<Uint8List> buildAlumnoReport({
    required Alumno alumno,
    required List<Evaluacion> evaluaciones,
    required CuadernoAlumnoView fila,
    required String claseNombre,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Informe del alumno')),
          pw.Text('${alumno.nombre} ${alumno.apellidos}'),
          pw.Text('Clase: $claseNombre'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Evaluación', 'Tipo', 'Valor'],
            data: evaluaciones
                .map(
                  (evaluacion) => [
                    evaluacion.nombre,
                    evaluacion.tipo,
                    fila.celdas[evaluacion.id]?.valor == null
                        ? '-'
                        : _numberFormat.format(fila.celdas[evaluacion.id]!.valor),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> buildClaseReport({
    required Clase clase,
    required CuadernoView cuaderno,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Resumen de clase')),
          pw.Text('${clase.nombre} - Curso ${clase.curso}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [
              'Alumno',
              ...cuaderno.evaluaciones.map((e) => e.codigo.toUpperCase()),
            ],
            data: cuaderno.filas
                .map(
                  (fila) => [
                    '${fila.alumno.apellidos}, ${fila.alumno.nombre}',
                    ...cuaderno.evaluaciones.map(
                      (evaluacion) {
                        final value = fila.celdas[evaluacion.id]?.valor;
                        return value == null ? '-' : _numberFormat.format(value);
                      },
                    ),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> buildRubricaReport(RubricaCompleta rubrica) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Ficha de rúbrica')),
          pw.Text(rubrica.rubrica.nombre),
          if ((rubrica.rubrica.descripcion ?? '').isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(rubrica.rubrica.descripcion!),
            ),
          pw.SizedBox(height: 16),
          ...rubrica.criterios.map(
            (criterio) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${criterio.criterio.descripcion} (${_numberFormat.format(criterio.criterio.peso)})',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Bullet(
                  text: criterio.niveles
                      .map((nivel) => '${nivel.nivel}: ${nivel.puntos} pts')
                      .join(' | '),
                ),
                pw.SizedBox(height: 8),
              ],
            ),
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Generado: ${_dateFormat.format(DateTime.now())}'),
          ),
        ],
      ),
    );

    return pdf.save();
  }
}
