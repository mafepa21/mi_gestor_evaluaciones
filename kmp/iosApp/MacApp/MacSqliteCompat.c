#include <sqlite3.h>

/*
 * Kotlin/Native + SQLiter can leave references to optional SQLite entrypoints
 * that are not exported by Apple's system SQLite on macOS.
 * These compatibility shims keep the app linkable; the affected APIs are not
 * part of the app's runtime path for this target.
 */

int sqlite3_enable_load_extension(sqlite3 *db, int onoff) {
    (void)db;
    (void)onoff;
    return SQLITE_ERROR;
}

int sqlite3_load_extension(sqlite3 *db, const char *zFile, const char *zProc, char **pzErrMsg) {
    (void)db;
    (void)zFile;
    (void)zProc;
    if (pzErrMsg != 0) {
        *pzErrMsg = 0;
    }
    return SQLITE_ERROR;
}

int sqlite3_mutex_held(sqlite3_mutex *p) {
    (void)p;
    return 1;
}

int sqlite3_mutex_notheld(sqlite3_mutex *p) {
    (void)p;
    return 1;
}

int sqlite3_unlock_notify(sqlite3 *pBlocked, void (*xNotify)(void **, int), void *pNotifyArg) {
    (void)pBlocked;
    (void)xNotify;
    (void)pNotifyArg;
    return SQLITE_ERROR;
}

int sqlite3_win32_set_directory(unsigned long type, void *zValue) {
    (void)type;
    (void)zValue;
    return SQLITE_ERROR;
}

int sqlite3_win32_set_directory8(unsigned long type, const char *zValue) {
    (void)type;
    (void)zValue;
    return SQLITE_ERROR;
}

int sqlite3_win32_set_directory16(unsigned long type, const void *zValue) {
    (void)type;
    (void)zValue;
    return SQLITE_ERROR;
}
