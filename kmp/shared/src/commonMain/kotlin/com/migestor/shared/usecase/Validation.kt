package com.migestor.shared.usecase

internal fun requireNotBlank(value: String, field: String) {
    require(value.isNotBlank()) { "$field no puede estar vacío" }
}

internal fun requirePositive(value: Double, field: String) {
    require(value > 0.0) { "$field debe ser mayor que cero" }
}
