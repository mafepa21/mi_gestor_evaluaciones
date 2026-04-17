package com.migestor.data.platform

import app.cash.sqldelight.db.SqlDriver

private const val IOS_DB_NAME = "mi_gestor_kmp.db"
private const val IOS_APP_SUPPORT_DIR = "MiGestorKMPiOS"

fun createIosDriver(): SqlDriver = createAppleDriver(
    appSupportDirectoryName = IOS_APP_SUPPORT_DIR,
    databaseName = IOS_DB_NAME,
)

fun getIosAppDataPath(fileName: String): String = appleAppSupportPath(
    appSupportDirectoryName = IOS_APP_SUPPORT_DIR,
    fileName = fileName,
)
