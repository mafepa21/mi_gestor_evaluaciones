package com.migestor.shared.usecase

expect class Lock() {
    fun lock()
    fun unlock()
}

inline fun <T> Lock.withLock(action: () -> T): T {
    lock()
    try {
        return action()
    } finally {
        unlock()
    }
}
