# Autoevaluación del rol Coach publicable — 2026-07-31

## Alcance

Se prepara para la SA 1 `Building Health` el instrumento auxiliar `Quiz de cierre del rol Coach y
Pasaporte Saludable`.

- Cinco respuestas `SCALE_1_4`: registro, seguridad, feedback, cooperación y próximo paso.
- Dos respuestas `TEXT`: evidencia del feedback y compromiso de mejora.
- Sin peso propio: la evidencia apoya la rejilla transversal CE 3.2 y no modifica la fórmula de la
  SA (`40 + 35 + 15 + 10 = 100`).

## Flujo de datos

1. Al importar el DOCX de la SA, la app crea la columna auxiliar y su plantilla estructurada.
2. Al publicarla, `WebSubmissionPublisher` convierte los ítems existentes en el manifiesto firmado
   y genera un enlace individual para cada alumno/a.
3. La PWA sirve el manifiesto desde `entregas-alumnado`; la entrega cifrada vuelve a la plantilla y
   a la columna de quien ha respondido.

No se registra una calificación automática ni se intenta atribuir una valoración a otro alumno/a.
La coevaluación se conserva como evidencia del feedback emitido, que es el dato que el flujo actual
puede atribuir de forma segura.

## Verificación

- `pandoc instrumentos_evaluacion.md -o instrumentos_evaluacion.docx`: correcto.
- El `word/document.xml` del DOCX generado contiene el título y los ítems extremos del instrumento.
- `scripts/verify_apple_builds.sh`: no concluyó durante esta sesión porque el entorno tuvo que
  descargar Gradle/KMP. La primera ejecución tampoco pudo resolver los paquetes Swift por DNS
  aislado. No se ha obtenido ningún error de compilación del código; queda pendiente una
  compilación completa desde Xcode o con caché de dependencias.
