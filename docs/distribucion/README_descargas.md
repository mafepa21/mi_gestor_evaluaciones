# Cuaderno Vivo

**Tu cuaderno de profe para Mac.** Notas, rúbricas, asistencia, planificación e informes en un solo sitio, con tus datos guardados en tu propio ordenador.

## Descargar

1. Ve a [**Releases**](https://github.com/mafepa21/cuaderno-vivo/releases/latest).
2. Descarga el archivo `CuadernoVivo-<versión>.dmg`.

Necesitas un Mac con chip Apple (M1 o posterior) y macOS 26 o posterior.

## Instalar

1. Abre el archivo `.dmg` que has descargado.
2. Arrastra **Cuaderno Vivo** a la carpeta **Aplicaciones**.
3. Abre **Cuaderno Vivo** desde Aplicaciones.

### La primera vez: «Abrir igualmente»

Cuaderno Vivo es un proyecto personal y no está firmado con una cuenta de pago de Apple. Por eso, la primera vez que la abres, el Mac muestra un aviso y no la deja arrancar. Es normal. Para permitirla:

1. Cierra el aviso.
2. Abre **Ajustes del Sistema** > **Privacidad y seguridad**.
3. Baja hasta el final. Verás un mensaje sobre Cuaderno Vivo.
4. Pulsa **Abrir igualmente** y escribe tu contraseña del Mac.

Solo hay que hacerlo una vez por cada versión nueva.

## Actualizar

Descarga el `.dmg` nuevo y arrastra la app a Aplicaciones otra vez. Pulsa **Reemplazar**. Tus datos no se borran: se guardan aparte de la app.

## Comprobar la descarga (opcional)

Cada versión incluye un archivo `.sha256`. En la app Terminal:

```bash
shasum -a 256 ~/Downloads/CuadernoVivo-<versión>.dmg
```

El número que sale debe ser igual al del archivo `.sha256`.

## Tus datos

- Tu cuaderno se guarda en tu Mac, no en la nube.
- La app solo se conecta a internet si usas las entregas web del alumnado.
- Haz copias de seguridad desde la propia app de vez en cuando.

## Problemas o ideas

Abre un aviso en [**Issues**](https://github.com/mafepa21/cuaderno-vivo/issues). Cuenta qué hiciste y qué pasó. Nunca pegues datos reales de alumnos.
