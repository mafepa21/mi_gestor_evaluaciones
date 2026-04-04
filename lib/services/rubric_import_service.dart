import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

class ImportedRubric {
  const ImportedRubric({
    required this.title,
    required this.levels,
    required this.criteria,
  });

  final String title;
  final List<ImportedRubricLevel> levels;
  final List<ImportedRubricCriterion> criteria;
}

class ImportedRubricLevel {
  const ImportedRubricLevel({
    required this.name,
    required this.points,
  });

  final String name;
  final int points;
}

class ImportedRubricCriterion {
  const ImportedRubricCriterion({
    required this.name,
    required this.cells,
  });

  final String name;
  final List<String> cells;
}

class RubricImportService {
  const RubricImportService._();

  static ImportedRubric parseFile(
    Uint8List bytes, {
    required String fileName,
    String fallbackTitle = 'Rúbrica importada',
  }) {
    final normalized = fileName.toLowerCase();
    if (normalized.endsWith('.csv')) {
      return _parseRows(
        _parseCsv(bytes),
        fallbackTitle: fallbackTitle,
      );
    }

    return parseXlsx(
      bytes,
      fallbackTitle: fallbackTitle,
    );
  }

  static ImportedRubric parseXlsx(
    Uint8List bytes, {
    String fallbackTitle = 'Rúbrica importada',
  }) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('El archivo no contiene hojas legibles.');
    }

    final sheet = excel.tables.values.first;
    final rows = sheet.rows
        .map((row) => row.map(_cellText).toList(growable: false))
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList(growable: false);

    return _parseRows(rows, fallbackTitle: fallbackTitle);
  }

  static ImportedRubric _parseRows(
    List<List<String>> rows, {
    required String fallbackTitle,
  }) {
    if (rows.isEmpty) {
      throw const FormatException('La hoja está vacía.');
    }

    final headerRowIndex = rows.indexWhere(_looksLikeHeaderRow);
    if (headerRowIndex == -1) {
      throw const FormatException(
        'No se ha encontrado una fila de cabecera con criterios y niveles.',
      );
    }

    final titleRows = rows.take(headerRowIndex).toList(growable: false);
    final headerRow = rows[headerRowIndex];
    final criterionColumnIndex = _findCriterionColumn(headerRow);
    final levelColumns = <int>[
      for (var index = 0; index < headerRow.length; index++)
        if (index != criterionColumnIndex && headerRow[index].trim().isNotEmpty)
          index,
    ];

    if (levelColumns.length < 2) {
      throw const FormatException(
        'La rúbrica debe tener al menos una columna de criterio y dos niveles.',
      );
    }

    final levels = <ImportedRubricLevel>[
      for (var position = 0; position < levelColumns.length; position++)
        ImportedRubricLevel(
          name: headerRow[levelColumns[position]].trim(),
          points: _extractPoints(
            headerRow[levelColumns[position]],
            position: position,
            totalLevels: levelColumns.length,
          ),
        ),
    ];

    final criteria = <ImportedRubricCriterion>[];
    for (final row in rows.skip(headerRowIndex + 1)) {
      final rowHasEnoughData =
          row.where((cell) => cell.trim().isNotEmpty).length >= 2;
      if (!rowHasEnoughData || criterionColumnIndex >= row.length) {
        continue;
      }

      final criterionName = row[criterionColumnIndex].trim();
      if (criterionName.isEmpty) {
        continue;
      }

      final cells = <String>[
        for (final columnIndex in levelColumns)
          columnIndex < row.length ? row[columnIndex].trim() : '',
      ];

      if (cells.every((cell) => cell.isEmpty)) {
        continue;
      }

      criteria.add(
        ImportedRubricCriterion(
          name: criterionName,
          cells: cells,
        ),
      );
    }

    if (criteria.isEmpty) {
      throw const FormatException(
        'No se han encontrado filas de criterios debajo de la cabecera.',
      );
    }

    final title = titleRows
        .expand((row) => row)
        .map((cell) => cell.trim())
        .firstWhere(
          (cell) => cell.isNotEmpty && !_looksLikeHeaderLabel(cell),
          orElse: () => fallbackTitle,
        );

    return ImportedRubric(
      title: title,
      levels: levels,
      criteria: criteria,
    );
  }

  static bool _looksLikeHeaderRow(List<String> row) {
    final nonEmptyCount = row.where((cell) => cell.trim().isNotEmpty).length;
    if (nonEmptyCount < 3) {
      return false;
    }

    final normalized = row.map((cell) => cell.trim().toLowerCase()).toList();
    final hasCriterionLabel = normalized.any(
      (cell) =>
          cell.contains('criterio') ||
          cell.contains('habilidad') ||
          cell.contains('indicador') ||
          cell.contains('aspecto'),
    );
    final scoredHeaders = normalized.where(_looksLikeScoreHeader).length;
    return hasCriterionLabel || scoredHeaders >= 2;
  }

  static int _findCriterionColumn(List<String> row) {
    final labeledIndex = row.indexWhere(
      (cell) {
        final normalized = cell.trim().toLowerCase();
        return normalized.contains('criterio') ||
            normalized.contains('habilidad') ||
            normalized.contains('indicador') ||
            normalized.contains('aspecto');
      },
    );

    if (labeledIndex != -1) {
      return labeledIndex;
    }

    return row.indexWhere((cell) => cell.trim().isNotEmpty);
  }

  static int _extractPoints(
    String header, {
    required int position,
    required int totalLevels,
  }) {
    final rangeMatch = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(header);
    if (rangeMatch != null) {
      return int.parse(rangeMatch.group(2)!);
    }

    final numbers = RegExp(r'\d+').allMatches(header).map((m) => m.group(0)!);
    if (numbers.isNotEmpty) {
      return int.parse(numbers.last);
    }

    if (totalLevels == 1) {
      return 10;
    }

    final ratio = (position + 1) / totalLevels;
    return max(1, (ratio * 10).round());
  }

  static List<List<String>> _parseCsv(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final rows = <List<String>>[];
    final row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    String delimiter = ';';

    final firstLine = text.split(RegExp(r'\r?\n')).firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '',
        );
    if (firstLine.contains(';')) {
      delimiter = ';';
    } else if (firstLine.contains(',')) {
      delimiter = ',';
    } else if (firstLine.contains('\t')) {
      delimiter = '\t';
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '"') {
        final nextIsQuote = i + 1 < text.length && text[i + 1] == '"';
        if (inQuotes && nextIsQuote) {
          cell.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (!inQuotes && char == delimiter) {
        row.add(cell.toString().trim());
        cell.clear();
        continue;
      }

      if (!inQuotes && (char == '\n' || char == '\r')) {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i++;
        }
        row.add(cell.toString().trim());
        cell.clear();
        if (row.any((value) => value.isNotEmpty)) {
          rows.add(List<String>.from(row));
        }
        row.clear();
        continue;
      }

      cell.write(char);
    }

    row.add(cell.toString().trim());
    if (row.any((value) => value.isNotEmpty)) {
      rows.add(List<String>.from(row));
    }

    return rows;
  }

  static bool _looksLikeScoreHeader(String value) {
    return value.contains('(') ||
        value.contains('nivel') ||
        value.contains('insuficiente') ||
        value.contains('suficiente') ||
        value.contains('bien') ||
        value.contains('excelente');
  }

  static bool _looksLikeHeaderLabel(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.contains('criterio') ||
        normalized.contains('habilidad') ||
        normalized.contains('indicador') ||
        normalized.contains('aspecto');
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
}
