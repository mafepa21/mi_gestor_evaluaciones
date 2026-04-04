package com.migestor.data.platform

import android.content.Context
import app.cash.sqldelight.driver.android.AndroidSqliteDriver
import com.migestor.data.db.AppDatabase

fun createAndroidDriver(context: Context): AndroidSqliteDriver {
    return AndroidSqliteDriver(
        schema = AppDatabase.Schema,
        context = context,
        name = "mi_gestor_kmp.db",
    )
}
