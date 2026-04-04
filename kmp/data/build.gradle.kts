plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("com.android.library")
    id("app.cash.sqldelight")
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }
    jvm("desktop")
    iosArm64()
    iosSimulatorArm64()

    targets.withType(org.jetbrains.kotlin.gradle.plugin.mpp.KotlinNativeTarget::class.java).configureEach {
        binaries.framework {
            baseName = "MiGestorKit"
            isStatic = true
            export(project(":shared"))
            export("org.jetbrains.kotlinx:kotlinx-datetime:0.6.1")
            export("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                api(project(":shared"))
                implementation("app.cash.sqldelight:runtime:2.0.2")
                implementation("app.cash.sqldelight:coroutines-extensions:2.0.2")
                api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
                api("org.jetbrains.kotlinx:kotlinx-datetime:0.6.1")
            }
        }
        val androidMain by getting {
            dependencies {
                implementation("app.cash.sqldelight:android-driver:2.0.2")
            }
        }
        val desktopMain by getting {
            dependencies {
                implementation("app.cash.sqldelight:sqlite-driver:2.0.2")
                implementation("org.apache.poi:poi-ooxml:5.3.0")
                implementation("com.github.librepdf:openpdf:1.3.39")
            }
        }
        val iosMain by creating {
            dependsOn(commonMain)
            dependencies {
                implementation("app.cash.sqldelight:native-driver:2.0.2")
            }
        }
        val iosArm64Main by getting {
            dependsOn(iosMain)
        }
        val iosSimulatorArm64Main by getting {
            dependsOn(iosMain)
        }
        val desktopTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation("app.cash.sqldelight:sqlite-driver:2.0.2")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
            }
        }
    }
}

android {
    namespace = "com.migestor.data"
    compileSdk = 35
    defaultConfig {
        minSdk = 26
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

sqldelight {
    databases {
        create("AppDatabase") {
            packageName.set("com.migestor.data.db")
            dialect("app.cash.sqldelight:sqlite-3-35-dialect:2.0.2")
        }
    }
}
