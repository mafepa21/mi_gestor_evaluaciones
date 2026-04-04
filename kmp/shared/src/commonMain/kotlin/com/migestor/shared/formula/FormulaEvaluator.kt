package com.migestor.shared.formula

class FormulaEvaluator {
    fun evaluate(expression: String, variables: Map<String, Double>): Double {
        val parser = Parser(tokenize(expression), variables)
        return parser.parseExpression()
    }

    private fun tokenize(input: String): List<String> {
        val tokens = mutableListOf<String>()
        val current = StringBuilder()

        fun flushToken() {
            if (current.isNotEmpty()) {
                tokens += current.toString()
                current.clear()
            }
        }

        var i = 0
        while (i < input.length) {
            val char = input[i]
            when {
                char.isWhitespace() -> flushToken()
                i + 1 < input.length && "${input[i]}${input[i + 1]}" in setOf("<=", ">=", "==", "!=", "<>") -> {
                    flushToken()
                    tokens += "${input[i]}${input[i + 1]}"
                    i += 1
                }
                char in listOf('+', '-', '*', '/', '(', ')', ',', '<', '>') -> {
                    flushToken()
                    tokens += char.toString()
                }
                else -> current.append(char)
            }
            i += 1
        }
        flushToken()
        return tokens
    }

    private class Parser(
        private val tokens: List<String>,
        private val variables: Map<String, Double>,
    ) {
        private var pos: Int = 0

        fun parseExpression(): Double {
            val result = parseComparison()
            require(isAtEnd()) { "Token inesperado: ${peek()}" }
            return result
        }

        private fun parseComparison(): Double {
            var left = parseAddSub()
            while (match("<", ">", "<=", ">=", "==", "!=", "<>")) {
                val operator = previous()
                val right = parseAddSub()
                left = when (operator) {
                    "<" -> bool(left < right)
                    ">" -> bool(left > right)
                    "<=" -> bool(left <= right)
                    ">=" -> bool(left >= right)
                    "==", "=" -> bool(left == right)
                    "!=", "<>" -> bool(left != right)
                    else -> error("Operador no soportado: $operator")
                }
            }
            return left
        }

        private fun parseAddSub(): Double {
            var left = parseMulDiv()
            while (match("+", "-")) {
                val operator = previous()
                val right = parseMulDiv()
                left = if (operator == "+") left + right else left - right
            }
            return left
        }

        private fun parseMulDiv(): Double {
            var left = parseUnary()
            while (match("*", "/")) {
                val operator = previous()
                val right = parseUnary()
                left = when (operator) {
                    "*" -> left * right
                    "/" -> {
                        require(right != 0.0) { "División por cero" }
                        left / right
                    }
                    else -> error("Operador no soportado: $operator")
                }
            }
            return left
        }

        private fun parseUnary(): Double {
            if (match("-")) return -parseUnary()
            return parsePrimary()
        }

        private fun parsePrimary(): Double {
            if (match("(")) {
                val value = parseComparison()
                require(match(")")) { "Paréntesis desbalanceados" }
                return value
            }

            val token = advance()
            token.toDoubleOrNull()?.let { return it }

            if (isIdentifier(token)) {
                if (match("(")) {
                    val args = mutableListOf<Double>()
                    if (!check(")")) {
                        do {
                            args += parseComparison()
                        } while (match(","))
                    }
                    require(match(")")) { "Paréntesis desbalanceados en función $token" }
                    return evalFunction(token, args)
                }

                return variables[token]
                    ?: error("Variable no encontrada en fórmula: $token")
            }

            error("Token no soportado: $token")
        }

        private fun evalFunction(nameRaw: String, args: List<Double>): Double {
            val name = nameRaw.uppercase()
            return when (name) {
                "IF", "SI" -> {
                    require(args.size == 3) { "$name requiere 3 argumentos" }
                    if (args[0] != 0.0) args[1] else args[2]
                }
                "AND", "Y" -> bool(args.all { it != 0.0 })
                "OR", "O" -> bool(args.any { it != 0.0 })
                "NOT", "NO" -> {
                    require(args.size == 1) { "$name requiere 1 argumento" }
                    bool(args[0] == 0.0)
                }
                "SUM", "SUMA" -> args.sum()
                "AVG", "PROMEDIO", "AVERAGE" -> {
                    require(args.isNotEmpty()) { "$name requiere al menos 1 argumento" }
                    args.sum() / args.size
                }
                "MIN" -> {
                    require(args.isNotEmpty()) { "$name requiere al menos 1 argumento" }
                    args.minOrNull()!!
                }
                "MAX" -> {
                    require(args.isNotEmpty()) { "$name requiere al menos 1 argumento" }
                    args.maxOrNull()!!
                }
                "ROUND", "REDONDEAR" -> {
                    require(args.size in 1..2) { "$name requiere 1 o 2 argumentos" }
                    val digits = if (args.size == 2) args[1].toInt() else 0
                    round(args[0], digits)
                }
                else -> error("Función no soportada: $nameRaw")
            }
        }

        private fun round(value: Double, digits: Int): Double {
            val factor = 10.0.pow(digits)
            return kotlin.math.round(value * factor) / factor
        }

        private fun bool(value: Boolean): Double = if (value) 1.0 else 0.0

        private fun isIdentifier(value: String): Boolean = value.matches(Regex("[A-Za-z_][A-Za-z0-9_]*"))

        private fun match(vararg expected: String): Boolean {
            if (isAtEnd()) return false
            if (expected.any { check(it) }) {
                pos += 1
                return true
            }
            return false
        }

        private fun check(expected: String): Boolean {
            if (isAtEnd()) return false
            return peek() == expected
        }

        private fun advance(): String {
            require(!isAtEnd()) { "Expresión incompleta" }
            return tokens[pos++]
        }

        private fun previous(): String = tokens[pos - 1]
        private fun peek(): String = tokens[pos]
        private fun isAtEnd(): Boolean = pos >= tokens.size
    }

    companion object {
        private fun Double.pow(power: Int): Double {
            var result = 1.0
            repeat(kotlin.math.abs(power)) { result *= 10.0 }
            return if (power >= 0) result else 1.0 / result
        }
    }
}
