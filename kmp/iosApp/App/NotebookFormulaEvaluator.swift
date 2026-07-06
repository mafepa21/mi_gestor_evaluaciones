import Foundation

enum NotebookFormulaError: LocalizedError {
    case incompleteExpression
    case unexpectedToken(String)
    case unbalancedParentheses
    case unknownVariable(String)
    case unknownFunction(String)
    case invalidArguments(String)
    case divisionByZero

    var errorDescription: String? {
        switch self {
        case .incompleteExpression:
            return "Fórmula incompleta"
        case .unexpectedToken(let token):
            return "Token inesperado: \(token)"
        case .unbalancedParentheses:
            return "Paréntesis desbalanceados"
        case .unknownVariable(let name):
            return "Columna no encontrada: \(name)"
        case .unknownFunction(let name):
            return "Función no soportada: \(name)"
        case .invalidArguments(let message):
            return message
        case .divisionByZero:
            return "División por cero"
        }
    }
}

enum NotebookFormulaEvaluator {
    static func safeIdentifier(for raw: String) -> String {
        let mapped = raw.map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" {
                return character
            }
            return "_"
        }
        let identifier = String(mapped)
        if identifier.first?.isNumber == true {
            return "_\(identifier)"
        }
        return identifier
    }

    static func evaluate(_ expression: String, variables: [String: Double]) throws -> Double {
        let normalized = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "=" })
        var parser = Parser(tokens: tokenize(String(normalized)), variables: variables)
        return try parser.parseExpression()
    }

    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            if character.isWhitespace {
                flush()
            } else if character == "[" {
                flush()
                let nextIndex = input.index(after: index)
                if let end = input[nextIndex...].firstIndex(of: "]") {
                    let columnId = String(input[nextIndex..<end])
                    tokens.append(columnId)
                    index = end
                } else {
                    tokens.append(String(character))
                }
            } else if "+-*/();<>".contains(character) {
                flush()
                let nextIndex = input.index(after: index)
                if nextIndex < input.endIndex {
                    let pair = "\(character)\(input[nextIndex])"
                    if ["<=", ">=", "==", "!=", "<>"].contains(pair) {
                        tokens.append(pair)
                        index = nextIndex
                    } else {
                        tokens.append(String(character))
                    }
                } else {
                    tokens.append(String(character))
                }
            } else {
                current.append(character)
            }
            index = input.index(after: index)
        }
        flush()
        return tokens
    }

    private struct Parser {
        let tokens: [String]
        let variables: [String: Double]
        var position = 0

        mutating func parseExpression() throws -> Double {
            let result = try parseComparison()
            if !isAtEnd {
                throw NotebookFormulaError.unexpectedToken(peek)
            }
            return result
        }

        private mutating func parseComparison() throws -> Double {
            var left = try parseAddSub()
            while match("<", ">", "<=", ">=", "==", "!=", "<>") {
                let op = previous
                let right = try parseAddSub()
                switch op {
                case "<": left = left < right ? 1 : 0
                case ">": left = left > right ? 1 : 0
                case "<=": left = left <= right ? 1 : 0
                case ">=": left = left >= right ? 1 : 0
                case "==": left = left == right ? 1 : 0
                case "!=", "<>": left = left != right ? 1 : 0
                default: throw NotebookFormulaError.unexpectedToken(op)
                }
            }
            return left
        }

        private mutating func parseAddSub() throws -> Double {
            var left = try parseMulDiv()
            while match("+", "-") {
                let op = previous
                let right = try parseMulDiv()
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        private mutating func parseMulDiv() throws -> Double {
            var left = try parseUnary()
            while match("*", "/") {
                let op = previous
                let right = try parseUnary()
                if op == "/" {
                    guard right != 0 else { throw NotebookFormulaError.divisionByZero }
                    left /= right
                } else {
                    left *= right
                }
            }
            return left
        }

        private mutating func parseUnary() throws -> Double {
            if match("-") { return try -parseUnary() }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Double {
            if match("(") {
                let value = try parseComparison()
                guard match(")") else { throw NotebookFormulaError.unbalancedParentheses }
                return value
            }

            guard !isAtEnd else { throw NotebookFormulaError.incompleteExpression }
            let token = advance()
            if let number = Double(token.replacingOccurrences(of: ",", with: ".")) {
                return number
            }
            if match("(") {
                var args: [Double] = []
                if !check(")") {
                    repeat {
                        args.append(try parseComparison())
                    } while match(";")
                }
                guard match(")") else { throw NotebookFormulaError.unbalancedParentheses }
                return try evaluateFunction(token, args: args)
            }
            if let value = variables[token] ?? variables[NotebookFormulaEvaluator.safeIdentifier(for: token)] {
                return value
            }
            throw NotebookFormulaError.unknownVariable(token)
        }

        private func evaluateFunction(_ rawName: String, args: [Double]) throws -> Double {
            let name = rawName.uppercased()
            switch name {
            case "SUM", "SUMA":
                return args.reduce(0, +)
            case "AVG", "AVERAGE", "PROMEDIO":
                guard !args.isEmpty else { throw NotebookFormulaError.invalidArguments("\(rawName) requiere al menos 1 argumento") }
                return args.reduce(0, +) / Double(args.count)
            case "MIN":
                guard let value = args.min() else { throw NotebookFormulaError.invalidArguments("MIN requiere al menos 1 argumento") }
                return value
            case "MAX":
                guard let value = args.max() else { throw NotebookFormulaError.invalidArguments("MAX requiere al menos 1 argumento") }
                return value
            case "ROUND", "REDONDEAR":
                guard args.count == 1 || args.count == 2 else { throw NotebookFormulaError.invalidArguments("\(rawName) requiere 1 o 2 argumentos") }
                let digits = args.count == 2 ? Int(args[1]) : 0
                let factor = pow(10.0, Double(digits))
                return (args[0] * factor).rounded() / factor
            case "IF", "SI":
                guard args.count == 3 else { throw NotebookFormulaError.invalidArguments("\(rawName) requiere 3 argumentos") }
                return args[0] != 0 ? args[1] : args[2]
            default:
                throw NotebookFormulaError.unknownFunction(rawName)
            }
        }

        private mutating func match(_ expected: String...) -> Bool {
            guard !isAtEnd, expected.contains(peek) else { return false }
            position += 1
            return true
        }

        private func check(_ expected: String) -> Bool {
            !isAtEnd && peek == expected
        }

        private mutating func advance() -> String {
            let token = peek
            position += 1
            return token
        }

        private var previous: String { tokens[position - 1] }
        private var peek: String { tokens[position] }
        private var isAtEnd: Bool { position >= tokens.count }
    }
}
