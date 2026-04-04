plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("com.android.library")
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }
    jvm("desktop")
    iosArm64 {
        binaries.framework {
            baseName = "MiGestorKit"
            export("org.jetbrains.kotlinx:kotlinx-datetime:0.6.1")
            export("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
        }
    }
    iosSimulatorArm64 {
        binaries.framework {
            baseName = "MiGestorKit"
            export("org.jetbrains.kotlinx:kotlinx-datetime:0.6.1")
            export("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
                api("org.jetbrains.kotlinx:kotlinx-datetime:0.6.1")
            }
        }
        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
            }
        }
        val iosMain by creating {
            dependsOn(commonMain)
        }
        val iosArm64Main by getting {
            dependsOn(iosMain)
        }
        val iosSimulatorArm64Main by getting {
            dependsOn(iosMain)
        }
    }
    
    sourceSets.all {
        languageSettings.optIn("kotlin.experimental.ExperimentalObjCName")
    }
}

android {
    namespace = "com.migestor.shared"
    compileSdk = 35
    defaultConfig {
        minSdk = 26
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
