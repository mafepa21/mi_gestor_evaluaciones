package com.migestor.data.platform

import app.cash.sqldelight.db.SqlDriver

private const val MACOS_DB_NAME = "desktop_mi_gestor_kmp.db"
private const val MACOS_APP_SUPPORT_DIR = "MiGestor"
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

fun getMacosAppDataPath(fileName: String): String = appleAppSupportPath(
    appSupportDirectoryName = MACOS_APP_SUPPORT_DIR,
    fileName = fileName,
)
