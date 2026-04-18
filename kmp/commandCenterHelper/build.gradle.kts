import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.compose")
}

val jbrHomeCandidates = listOf(
    "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home",
    "/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home",
    System.getenv("JBR_HOME"),
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home",
    "/Applications/IntelliJ IDEA.app/Contents/jbr/Contents/Home",
).filterNotNull().map { file(it) }.filter { it.exists() }

val jbrHome = jbrHomeCandidates.firstOrNull {
    it.resolve("bin/jpackage").exists()
}?.absolutePath

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":shared"))
    implementation(project(":data"))
    implementation(compose.desktop.currentOs)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.6.1")
    implementation("app.cash.sqldelight:sqlite-driver:2.0.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    implementation("org.jmdns:jmdns:3.5.9")
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.78.1")
    implementation("org.slf4j:slf4j-simple:2.0.13")
}

compose.desktop {
    application {
        mainClass = "com.migestor.commandcenter.CommandCenterMainKt"
        jvmArgs += listOf("-Dcompose.application.configure.swing.globals=false")
        if (jbrHome != null) {
            javaHome = jbrHome
        }
        nativeDistributions {
            targetFormats(TargetFormat.Dmg)
            packageName = "MiGestorCommandCenter"
            packageVersion = "1.0.0"
            description = "Servidor LAN y centro de mando de MiGestor"
            vendor = "Mario Fernandez"
            modules(
                "java.sql",
                "java.naming",
                "java.logging",
                "java.management",
                "java.prefs",
                "jdk.httpserver",
                "jdk.crypto.ec",
            )

            macOS {
                bundleID = "com.migestor.commandcenter"
                packageVersion = "1.0.0"
            }
        }
    }
}
