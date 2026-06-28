package com.migestor.shared.usecase

import platform.Foundation.NSLock

actual class Lock actual constructor() {
    private val lock = NSLock()
    actual fun lock() = lock.lock()
    actual fun unlock() = lock.unlock()
}
