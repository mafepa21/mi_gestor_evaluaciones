package com.migestor.data.platform

import app.cash.sqldelight.db.SqlDriver

private const val MACOS_DB_NAME = "desktop_mi_gestor_kmp.db"
private const val MACOS_APP_SUPPORT_DIR = "MiGestor"
private const val MACOS_TEST_DB_NAME = "planner_tests.db"
private const val MACOS_TEST_APP_SUPPORT_DIR = "MiGestorTests"
private const val LEGACY_MACOS_DB_NAME = "mi_gestor_kmp.db"
private const val LEGACY_MACOS_APP_SUPPORT_DIR = "MiGestorKMPMac"

fun createMacosDriver(): SqlDriver = createAppleDriver(
    appSupportDirectoryName = MACOS_APP_SUPPORT_DIR,
    databaseName = MACOS_DB_NAME,
    legacySourcePaths = listOf(
        appleAppSupportPath(
            appSupportDirectoryName = LEGACY_MACOS_APP_SUPPORT_DIR,
            fileName = LEGACY_MACOS_DB_NAME,
        ),
        appleAppSupportPath(
            appSupportDirectoryName = "MiGestorKMP",
            fileName = MACOS_DB_NAME,
        ),
    ),
)

/** Driver aislado para el host de XCTest. Nunca debe abrir datos reales del usuario. */
fun createMacosTestDriver(): SqlDriver = createAppleDriver(
    appSupportDirectoryName = MACOS_TEST_APP_SUPPORT_DIR,
    databaseName = MACOS_TEST_DB_NAME,
)

fun getMacosTestDatabasePath(): String = appleAppSupportPath(
    appSupportDirectoryName = MACOS_TEST_APP_SUPPORT_DIR,
    fileName = MACOS_TEST_DB_NAME,
)

fun diagnoseMacosDriverBootstrap(): String {
    return try {
        val driver = createMacosDriver()
        driver.close()
        "OK"
    } catch (t: Throwable) {
        "${t::class.simpleName}: ${t.message}"
    }
}

fun getMacosAppDataPath(fileName: String): String = appleAppSupportPath(
    appSupportDirectoryName = MACOS_APP_SUPPORT_DIR,
    fileName = fileName,
)

/**
 * Nombre del fichero de base de datos que realmente abre la app macOS.
 *
 * Existe para que nadie vuelva a escribirlo a mano: hasta 2026-07 `AppleBridgeBootstrap`
 * usaba el nombre legacy `mi_gestor_kmp.db`, que en este directorio corresponde a un
 * fichero fantasma vacío. Consecuencia: las copias de seguridad de macOS se generaban
 * de 0 bytes y se reportaban como correctas, y restaurarlas no hacía nada.
 */
fun macosDatabaseFileName(): String = MACOS_DB_NAME

/** Ruta completa de la base de datos que abre la app macOS. */
fun getMacosDatabasePath(): String = getMacosAppDataPath(MACOS_DB_NAME)
