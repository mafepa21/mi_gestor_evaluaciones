# Third-Party Notices

Este inventario ayuda a preparar due diligence. No sustituye la revision final de
licencias ni el bundle de avisos que debe acompanarse a una release publica.

## Estado

| Area | Estado |
|---|---|
| Licencia del repo | Propietaria. Ver `LICENSE`. |
| Dependencias KMP activas | Inventariadas desde Gradle. |
| Dependencias Flutter legado | Inventariadas desde `pubspec.yaml`. |
| Licencias exactas por version | Pendiente de extraccion automatica antes de release. |
| Notices empaquetados | Pendiente de validar en apps iOS/macOS/desktop. |

## KMP, Android y Desktop

| Dependencia | Uso |
|---|---|
| Kotlin Multiplatform, Kotlin JVM, Kotlin Android | Modulos compartidos, Android y desktop. |
| Kotlinx Coroutines | Concurrencia y flujos asincronos. |
| Kotlinx Datetime | Fechas y calendarios multiplataforma. |
| Kotlinx Serialization JSON | Serializacion en servicios desktop/sync. |
| SQLDelight | Persistencia y drivers SQLite. |
| JetBrains Compose Desktop | App desktop Compose. |
| Android Gradle Plugin | Target Android KMP. |
| AndroidX Core, Activity, Lifecycle, Compose UI, Material3 | App Android KMP. |
| Ktor Server Netty y Content Negotiation | Servicios locales desktop/sync. |
| JmDNS | Descubrimiento local. |
| Bouncy Castle | Criptografia auxiliar. |
| Apache POI | Importacion/exportacion Excel. |
| OpenPDF | Generacion PDF desktop/data. |
| ZXing | Codigos QR o lectura de codigos. |
| SLF4J Simple | Logging desktop. |

## Apple

| Componente | Uso |
|---|---|
| SwiftUI, Foundation, AppKit/UIKit segun target | Apps iOS/iPadOS/macOS nativas. |
| XcodeGen | Generacion del proyecto Xcode para verificacion. |
| Apple Intelligence/Foundation Models si esta disponible | Funciones locales/contextuales de IA. |

Las APIs de Apple estan sujetas a las licencias y terminos de Apple Developer
Program y SDKs instalados localmente.

## Flutter legado

| Dependencia | Uso historico |
|---|---|
| Flutter SDK y Cupertino Icons | App Flutter original. |
| Drift y Drift Flutter | Persistencia Flutter. |
| Flutter Riverpod | Estado Flutter. |
| Intl | Localizacion y formatos. |
| Path y Path Provider | Rutas de archivos. |
| PDF y Printing | Informes e impresion. |
| Pluto Grid | Tablas. |
| RxDart | Streams reactivos. |
| Table Calendar | Calendario. |
| File Picker | Seleccion de archivos. |
| Excel | Hojas de calculo. |
| Flutter Lints, Build Runner, Drift Dev | Desarrollo y generacion. |

## Accion obligatoria antes de release

1. Generar un reporte de licencias por ecosistema: Gradle/KMP, Flutter/Dart,
   CocoaPods si aplica y Swift Package Manager si se anade.
2. Confirmar compatibilidad de licencias con distribucion comercial propietaria.
3. Copiar avisos requeridos por cada dependencia en el bundle final.
4. Revisar dependencias transitivas, no solo directas.
5. Registrar excepciones o restricciones en `docs/04_legal_comercial/due_diligence.md`.
