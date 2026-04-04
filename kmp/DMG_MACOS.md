# Crear el DMG de MiGestor en macOS

Esta guía resume el proceso completo para generar de nuevo el instalador `.dmg` de `MiGestor` desde cero.

## Requisitos

- Estar en macOS.
- Tener instalado un JDK 17 compatible con Compose Desktop.
- En este proyecto se usa preferentemente Temurin 17 en:
  - `/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home`
- Trabajar desde la carpeta `kmp/`.

## Comando rapido

Desde la raiz del proyecto:

```bash
cd kmp
./scripts/package_mac.sh
```

Ese script ejecuta:

```bash
./gradlew :desktopApp:packageDmg
```

## Paso a paso desde cero

1. Abre Terminal.
2. Ve al modulo desktop:

```bash
cd /Users/mariofernandez/Projects/mi_gestor_evaluaciones/kmp
```

3. Comprueba que el JDK 17 esta disponible:

```bash
ls /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
```

4. Genera el `.dmg`:

```bash
./gradlew :desktopApp:packageDmg
```

5. Localiza el instalador generado en:

```text
desktopApp/build/compose/binaries/main/dmg/MiGestor-1.0.0.dmg
```

## Si solo quieres el `.app`

Para obtener la app sin instalador:

```bash
./gradlew :desktopApp:createDistributable
```

El bundle queda en:

```text
desktopApp/build/compose/binaries/main/app/
```

## Si la app se cierra al abrirla

Ejecuta la app desde Terminal para ver el error real:

```bash
/Applications/MiGestor.app/Contents/MacOS/MiGestor 2>&1 | tee ~/Desktop/migestor_crash.log
```

Si falla por un modulo JVM faltante, revisa el bloque `compose.desktop { nativeDistributions { modules(...) } }` en:

- `desktopApp/build.gradle.kts`

## Notas utiles

- El `mainClass` actual es `com.migestor.desktop.MainKt`.
- El `bundleID` configurado es `com.migestor.app`.
- El nombre de paquete es `MiGestor`.
