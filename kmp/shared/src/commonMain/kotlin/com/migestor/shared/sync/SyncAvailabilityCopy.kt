package com.migestor.shared.sync

object SyncAvailabilityCopy {
    fun status(startError: String?, isPaired: Boolean): String = when {
        !startError.isNullOrBlank() -> "El enlace local no arrancó. $startError"
        isPaired -> "Vinculado"
        else -> "Esperando emparejamiento"
    }
}
