package com.migestor.data.platform

import android.content.Context
import app.cash.sqldelight.driver.android.AndroidSqliteDriver
import com.migestor.data.db.AppDatabase

fun createAndroidDriver(context: Context): AndroidSqliteDriver {
    val driver = AndroidSqliteDriver(
        schema = AppDatabase.Schema,
        context = context,
        name = "mi_gestor_kmp.db",
    )
    runRescueMigrations(driver)
    return driver
}
