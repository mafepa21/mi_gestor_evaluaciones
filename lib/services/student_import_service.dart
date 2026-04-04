import 'dart:typed_data';

import 'package:excel/excel.dart';

class StudentImportSheet {
  const StudentImportSheet({
    required this.students,
    this.schoolName,
    this.schoolYear,
    this.subject,
    this.classLabel,
    this.teacher,
    this.tutor,
  });

  final String? schoolName;
  final String? schoolYear;
  final String? subject;
  final String? classLabel;
  final String? teacher;
  final String? tutor;
  final List<StudentImportEntry> students;
}

class StudentImportEntry {
  const StudentImportEntry({
    required this.fullName,
    required this.nombre,
    required this.apellidos,
  });

  final String fullName;
  final String nombre;
  final String apellidos;
}

class StudentImportService {
  const StudentImportService._();

  static StudentImportSheet parseXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('El archivo no contiene hojas legibles.');
    }

    final sheet = excel.tables.values.first;
    final students = <StudentImportEntry>[];
    final seenStudents = <String>{};
    String? schoolName;
    String? schoolYear;
    String? subject;
    String? classLabel;
    String? teacher;
    String? tutor;

    for (final row in sheet.rows) {
      final values = row.map(_cellText).toList(growable: false);
      final nonEmpty = values.where((value) => value.isNotEmpty).toList();
      if (nonEmpty.isEmpty) {
        continue;
      }

      final combined = nonEmpty.join(' ').trim();
      schoolName ??= _looksLikeSchoolName(combined) ? combined : null;
      schoolYear ??= _extractLabeledValue(combined, 'Curso escolar');
      subject ??= _extractLabeledValue(combined, 'Materia');
      classLabel ??= _extractLabeledValue(combined, 'Clase');
      teacher ??= _extractLabeledValue(combined, 'Profesor');
      tutor ??= _extractLabeledValue(combined, 'Tutora') ??
          _extractLabeledValue(combined, 'Tutor');

      final student = _parseStudent(values);
      if (student == null) {
        continue;
      }

      final normalizedKey = _normalize(student.fullName);
      if (seenStudents.add(normalizedKey)) {
        students.add(student);
      }
    }

    if (students.isEmpty) {
      throw const FormatException(
        'No se han encontrado filas de alumnos con el formato esperado.',
      );
    }

    return StudentImportSheet(
      schoolName: schoolName,
      schoolYear: schoolYear,
      subject: subject,
      classLabel: classLabel,
      teacher: teacher,
      tutor: tutor,
      students: students,
    );
  }

  static StudentImportEntry? _parseStudent(List<String> values) {
    for (var index = 0; index < values.length; index++) {
      final current = values[index];
      if (!_isListIndex(current)) {
        continue;
      }

      final name = values.skip(index + 1).firstWhere(
            (value) => value.isNotEmpty && !_isListIndex(value),
            orElse: () => '',
          );
      if (name.isEmpty) {
        return null;
      }

      return _splitFullName(name);
    }

    return null;
  }

  static StudentImportEntry _splitFullName(String rawName) {
    final fullName = rawName.replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = fullName.split(' ');

    if (parts.length == 1) {
      return StudentImportEntry(
        fullName: fullName,
        nombre: parts.first,
        apellidos: '',
      );
    }

    if (parts.length == 2) {
      return StudentImportEntry(
        fullName: fullName,
        nombre: parts.first,
        apellidos: parts.last,
      );
    }

    final apellidoStart = parts.length >= 4 ? parts.length - 2 : parts.length - 1;
    return StudentImportEntry(
      fullName: fullName,
      nombre: parts.sublist(0, apellidoStart).join(' '),
      apellidos: parts.sublist(apellidoStart).join(' '),
    );
  }

  static String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) {
      return '';
    }

    return switch (value) {
      TextCellValue text => text.value.text?.trim() ?? '',
      _ => value.toString().trim(),
    };
  }

  static bool _looksLikeSchoolName(String text) {
    final upper = text.toUpperCase();
    return upper.contains('COLEGIO') || upper.contains('IES') || upper.contains('CEIP');
  }

  static String? _extractLabeledValue(String text, String label) {
    final regex = RegExp(
      '^${RegExp.escape(label)}\\s*:\\s*(.+)\$',
      caseSensitive: false,
    );
    final match = regex.firstMatch(text);
    return match?.group(1)?.trim();
  }

  static bool _isListIndex(String value) {
    return RegExp(r'^\d+\.?$').hasMatch(value.trim());
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
