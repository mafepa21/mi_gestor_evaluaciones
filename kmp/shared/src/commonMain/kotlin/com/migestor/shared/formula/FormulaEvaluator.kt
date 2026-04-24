package com.migestor.shared.formula

class FormulaEvaluator {
    fun evaluate(expression: String, variables: Map<String, Double>): Double {
        val normalized = expression
            .trim()
            .dropWhile { it == '=' }
        val parser = Parser(tokenize(normalized))
        return parser.parseExpression().evaluate(variables)
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
                char == '[' -> {
                    flushToken()
                    val end = input.indexOf(']', startIndex = i + 1)
                    if (end >= 0) {
                        tokens += input.substring(i + 1, end)
                        i = end
                    } else {
                        tokens += char.toString()
                    }
                }
                char in listOf('+', '-', '*', '/', '(', ')', ',', '<', '>', '=') -> {
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

    private sealed interface Node {
        fun evaluate(variables: Map<String, Double>): Double
    }

    private data class NumberNode(val value: Double) : Node {
        override fun evaluate(variables: Map<String, Double>): Double = value
    }

    private data class VariableNode(val name: String) : Node {
        override fun evaluate(variables: Map<String, Double>): Double {
            return variables[name] ?: error("Variable no encontrada en formula: $name")
        }
    }

    private data class UnaryNode(val operator: String, val value: Node) : Node {
        override fun evaluate(variables: Map<String, Double>): Double {
            val evaluated = value.evaluate(variables)
            return when (operator) {
                "-" -> -evaluated
                else -> error("Operador no soportado: $operator")
            }
        }
    }

    private data class BinaryNode(val left: Node, val operator: String, val right: Node) : Node {
        override fun evaluate(variables: Map<String, Double>): Double {
            val leftValue = left.evaluate(variables)
            val rightValue = right.evaluate(variables)
            return when (operator) {
                "+" -> leftValue + rightValue
                "-" -> leftValue - rightValue
                "*" -> leftValue * rightValue
                "/" -> {
                    require(rightValue != 0.0) { "Division por cero" }
                    leftValue / rightValue
                }
                "<" -> bool(leftValue < rightValue)
                ">" -> bool(leftValue > rightValue)
                "<=" -> bool(leftValue <= rightValue)
                ">=" -> bool(leftValue >= rightValue)
                "==", "=" -> bool(leftValue == rightValue)
                "!=", "<>" -> bool(leftValue != rightValue)
                else -> error("Operador no soportado: $operator")
            }
        }
    }

    private data class FunctionNode(val nameRaw: String, val args: List<Node>) : Node {
        override fun evaluate(variables: Map<String, Double>): Double {
            val name = nameRaw.uppercase()
            return when (name) {
                "IF", "SI" -> {
                    require(args.size == 3) { "$name requiere 3 argumentos" }
                    if (args[0].evaluate(variables) != 0.0) {
                        args[1].evaluate(variables)
                    } else {
                        args[2].evaluate(variables)
                    }
                }
                "AND", "Y" -> {
                    for (arg in args) {
                        if (arg.evaluate(variables) == 0.0) return 0.0
                    }
                    1.0
                }
                "OR", "O" -> {
                    for (arg in args) {
                        if (arg.evaluate(variables) != 0.0) return 1.0
                    }
                    0.0
                }
                "NOT", "NO" -> {
                    require(args.size == 1) { "$name requiere 1 argumento" }
                    bool(args[0].evaluate(variables) == 0.0)
                }
                "SUM", "SUMA" -> args.sumOf { it.evaluate(variables) }
                "AVG", "PROMEDIO", "AVERAGE" -> {
                    require(args.isNotEmpty()) { "$name requiere al menos 1 argumento" }
                    args.sumOf { it.evaluate(variables) } / args.size
                }
                "MIN" -> {
                    require(args.isNotEmpty()) { "$name requiere al menos 1 argumento" }
                    args.minOf { it.evaluate(variables) }
                }
                "MAX" -> {
                    require(args.isNotEmpty()) { "$name requiere al menos 1 argumento" }
                    args.maxOf { it.evaluate(variables) }
                }
                "ROUND", "REDONDEAR" -> {
                    require(args.size in 1..2) { "$name requiere 1 o 2 argumentos" }
                    val digits = if (args.size == 2) args[1].evaluate(variables).toInt() else 0
                    round(args[0].evaluate(variables), digits)
                }
                else -> error("Funcion no soportada: $nameRaw")
            }
        }
    }

    private class Parser(
        private val tokens: List<String>,
    ) {
        private var pos: Int = 0

        fun parseExpression(): Node {
            val result = parseComparison()
            require(isAtEnd()) { "Token inesperado: ${peek()}" }
            return result
        }

        private fun parseComparison(): Node {
            var left = parseAddSub()
            while (match("<", ">", "<=", ">=", "==", "=", "!=", "<>")) {
                val operator = previous()
                val right = parseAddSub()
                left = BinaryNode(left, operator, right)
            }
            return left
        }

        private fun parseAddSub(): Node {
            var left = parseMulDiv()
            while (match("+", "-")) {
                val operator = previous()
                val right = parseMulDiv()
                left = BinaryNode(left, operator, right)
            }
            return left
        }

        private fun parseMulDiv(): Node {
            var left = parseUnary()
            while (match("*", "/")) {
                val operator = previous()
                val right = parseUnary()
                left = BinaryNode(left, operator, right)
            }
            return left
        }

        private fun parseUnary(): Node {
            if (match("-")) return UnaryNode("-", parseUnary())
            return parsePrimary()
        }

        private fun parsePrimary(): Node {
            if (match("(")) {
                val value = parseComparison()
                require(match(")")) { "Parentesis desbalanceados" }
                return value
            }

            val token = advance()
            token.toDoubleOrNull()?.let { return NumberNode(it) }

            if (isIdentifier(token) && match("(")) {
                val args = mutableListOf<Node>()
                if (!check(")")) {
                    do {
                        args += parseComparison()
                    } while (match(","))
                }
                require(match(")")) { "Parentesis desbalanceados en funcion $token" }
                return FunctionNode(token, args)
            }

            if (isIdentifier(token)) {
                return VariableNode(token)
            }

            error("Token no soportado: $token")
        }

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
            require(!isAtEnd()) { "Expresion incompleta" }
            return tokens[pos++]
        }

        private fun previous(): String = tokens[pos - 1]
        private fun peek(): String = tokens[pos]
        private fun isAtEnd(): Boolean = pos >= tokens.size
    }

    companion object {
        private fun bool(value: Boolean): Double = if (value) 1.0 else 0.0

        private fun round(value: Double, digits: Int): Double {
            val factor = 10.0.pow(digits)
            return kotlin.math.round(value * factor) / factor
        }

        private fun Double.pow(power: Int): Double {
            var result = 1.0
            repeat(kotlin.math.abs(power)) { result *= 10.0 }
            return if (power >= 0) result else 1.0 / result
        }
    }
}
