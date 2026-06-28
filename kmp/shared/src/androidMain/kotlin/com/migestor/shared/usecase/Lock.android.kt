package com.migestor.shared.usecase

import java.util.concurrent.locks.ReentrantLock

actual class Lock actual constructor() {
    private val lock = ReentrantLock()
    actual fun lock() = lock.lock()
    actual fun unlock() = lock.unlock()
}
