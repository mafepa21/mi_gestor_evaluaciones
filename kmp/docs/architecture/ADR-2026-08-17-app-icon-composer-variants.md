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
- El paquete contiene una capa compartida con dos especializaciones de imagen:
  `AppIcon-1024.png` para `Default` y `AppIcon-1024-dark.png` para `Dark`.
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
