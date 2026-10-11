# ADR-2026-08-17: AppIcon compartido con Icon Composer

## Estado

Aprobado

## Contexto

Mi Gestor Evaluaciones comparte identidad visual entre iPadOS y macOS, pero el
icono debía resolver además las apariencias claro y oscuro del sistema. El
catálogo PNG tradicional con entradas `luminosity=dark` no estaba produciendo
rendiciones oscuras en el `Assets.car` generado por la toolchain actual de
Xcode, aunque el proyecto compilase correctamente.

## Decisión

- La fuente canónica del icono Apple será `kmp/iosApp/App/AppIcon.icon`, un
  paquete de Icon Composer cuyo nombre coincide con el App Icon configurado en
  los targets Apple.
- ~~El paquete contiene una capa compartida con dos especializaciones de imagen:
  `AppIcon-1024.png` para `Default` y `AppIcon-1024-dark.png` para `Dark`.~~
  Sustituido el 2026-10-11 (PR #314). Ver «Actualización 2026-10-11».
- XcodeGen incluirá `AppIcon.icon` como recurso de `MiGestorKMPiOS` y
  `MiGestorKMPMac`; Xcode generará los tamaños y las rendiciones específicas de
  cada plataforma.
- El antiguo `Assets.xcassets/AppIcon.appiconset` no se mantiene en paralelo,
  para evitar dos fuentes primarias del AppIcon y advertencias de catálogo.

## Consecuencias

- iPadOS y macOS reciben el mismo icono nativo y cambian automáticamente entre
  claro y oscuro según la apariencia del sistema.
- Los tamaños derivados se generan desde una única fuente, reduciendo el
  riesgo de desincronización entre plataformas.
- Las futuras modificaciones del icono deben editar `AppIcon.icon` y validar
  las rendiciones `Default` y `Dark` con `ictool`, además de compilar ambos
  targets Apple.

## Actualización 2026-10-11: icono «Cuadrícula de notas» en capas

### Contexto

El icono anterior (hoja con ✓) era genérico y parecía de una app de tareas.
Además, los dos PNG llevaban las esquinas redondeadas y la sombra pintadas, así
que con la máscara de iOS 26 / macOS 26 podía verse un cuadrado dentro de otro,
y el efecto Liquid Glass estaba apagado.

### Decisión

- El icono pasa a ser una cuadrícula de cuaderno de notas: cabecera, columna de
  nombres, fila del alumno marcada y una celda encendida (la nota que se pone).
- `AppIcon.icon` deja de usar PNG y se compone de capas planas:
  - Fondo: color sólido a sangre definido en `icon.json` con
    `fill-specializations`: añil `#3A4FD9` en `Default` y `#161B33` en `Dark`.
  - `Assets/Rejilla.svg`: cabecera, nombres, fila marcada y celdas en blanco
    translúcido; sin cristal.
  - `Assets/CeldaViva.svg`: celda blanca sólida; grupo superior con Liquid
    Glass, especular y traslucidez 0,2.
- Las capas SVG usan un lienzo de 1024 × 1024 (`viewBox` 160 × 160) con
  transparencia alrededor; el sistema aplica la máscara y las esquinas. No se
  pintan esquinas ni sombras en las capas.
- En `groups`, el primer grupo es el que queda delante.

### Consecuencias

- Un solo diseño para iPhone, iPad y Mac, con variantes claro, oscuro, tintado
  y transparente generadas por el sistema a partir de las capas.
- `actool` sigue generando PNG de reserva para el despliegue mínimo (iOS 17).
- `icon.json` se escribió a mano; se puede abrir y ajustar en Icon Composer.
- Validación usada: `ictool` (rendiciones iOS `Default`, `Dark`,
  `ClearLight`, `TintedDark` y macOS `Default`) más `xcodebuild` de
  `MiGestorKMPiOS` (iOS Simulator) y `MiGestorKMPMac` (`arch=arm64`). `ictool`
  necesita ejecutarse fuera del sandbox de Claude Code.
