class FormulaEvaluator {
  const FormulaEvaluator._();

  static double? evaluate(
    String? formula,
    Map<String, double?> values,
  ) {
    if (formula == null || formula.trim().isEmpty) {
      return null;
    }

    final parser = _FormulaParser(
      source: formula,
      values: {
        for (final entry in values.entries)
          normalizeIdentifier(entry.key): entry.value ?? 0,
      },
    );

    return parser.parse();
  }

  static String normalizeIdentifier(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}

class _FormulaParser {
  _FormulaParser({required this.source, required this.values});

  final String source;
  final Map<String, double> values;
  late final List<String> _tokens = _tokenize(source);
  int _index = 0;

  double? parse() {
    try {
      if (_tokens.isEmpty) {
        return null;
      }

      final result = _parseExpression();
      return result.isFinite ? result : null;
    } catch (_) {
      return null;
    }
  }

  double _parseExpression() {
    var result = _parseTerm();

    while (_match('+') || _match('-')) {
      final operator = _previous();
      final right = _parseTerm();
      result = operator == '+' ? result + right : result - right;
    }

    return result;
  }

  double _parseTerm() {
    var result = _parseFactor();

    while (_match('*') || _match('/')) {
      final operator = _previous();
      final right = _parseFactor();
      result = operator == '*' ? result * right : result / right;
    }

    return result;
  }

  double _parseFactor() {
    if (_match('-')) {
      return -_parseFactor();
    }

    if (_match('(')) {
      final inner = _parseExpression();
      _consume(')');
      return inner;
    }

    final token = _advance();
    final number = double.tryParse(token);
    if (number != null) {
      return number;
    }

    return values[FormulaEvaluator.normalizeIdentifier(token)] ?? 0;
  }

  bool _match(String token) {
    if (_isAtEnd || _tokens[_index] != token) {
      return false;
    }
    _index++;
    return true;
  }

  void _consume(String token) {
    if (!_match(token)) {
      throw StateError('Token esperado: $token');
    }
  }

  String _advance() {
    if (_isAtEnd) {
      throw StateError('Fin inesperado de formula');
    }
    return _tokens[_index++];
  }

  String _previous() => _tokens[_index - 1];

  bool get _isAtEnd => _index >= _tokens.length;

  List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();

    void flushBuffer() {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
    }

    for (final char in input.split('')) {
      if ('()+-*/'.contains(char)) {
        flushBuffer();
        tokens.add(char);
      } else if (char.trim().isEmpty) {
        flushBuffer();
      } else {
        buffer.write(char);
      }
    }

    flushBuffer();
    return tokens;
  }
}
