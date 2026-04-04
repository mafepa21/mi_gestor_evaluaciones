# Guía Técnica de Diseño - MiGestor KMP Desktop

Esta guía explica la estructura y funcionalidad de la aplicación para que el equipo de diseño pueda rediseñar una experiencia de usuario intuitiva y moderna, manteniendo la integridad de los datos.

## 🎨 Concepto de Diseño: "Organic Precision" (v2.2)
El sistema actual sigue reglas estrictas para garantizar un acabado profesional:
- **Geometría de 8pt**: Todo el espaciado (padding, margin) y los tamaños deben ser múltiplos de 8dp.
- **Micro-interacciones**: La interfaz debe sentirse viva, con efectos de hover delicados y transiciones suaves.
- **Tarjetas "Glass"**: Uso de `OrganicGlassCard` para agrupar información con efectos de transparencia y desenfoque (blur).

---

## 🏗️ Arquitectura de la Aplicación
La aplicación está organizada en **6 secciones principales (Tabs)**. Actualmente todas comparten una estructura de columna con un TabRow superior.

### 1. Dashboard (Panel Principal)
**Propósito**: Visión general del estado del profesor/centro.
- **Datos expuestos**:
  - Contadores totales: Alumnos, Clases, Evaluaciones, Rúbricas y Sesiones.
- **Acciones**: Botón para refrescar estadísticas.

### 2. Cuaderno (Core del Sistema)
**Propósito**: Es el "Excel inteligente" donde ocurre la magia. Es la pantalla más compleja y crítica.
- **Sub-apartados**:
  - **Gestión**: Creación rápida de Alumnos, Clases y Evaluaciones.
  - **Carga de Datos**: Botón para cargar la hoja de cálculo generada dinámicamente.
  - **Hoja (Sheet)**: Vista tabular (Spreadsheet) organizada por pestañas internas (ej. Evaluación, Pruebas, Bloques).
- **Tipos de datos en columnas**:
  - **Numéricos**: Notas de exámenes o tareas.
  - **Texto/Icono**: Observaciones o indicadores visuales.
  - **Check**: Seguimiento de tareas o asistencia.
  - **Calculados**: Columnas automáticas basadas en fórmulas (ej. `ROUND((EX1 * 0.4) + (TA1 * 0.6), 2)`).
- **Interacción**: El usuario debe poder editar celdas, guardar cambios en bloque y añadir nuevas columnas de cálculo al vuelo.

### 3. Planificación
**Propósito**: Organización temporal del curso.
- **Jerarquía de datos**:
  - **Periodos**: (ej. 1º Trimestre) que tienen fechas de inicio y fin.
  - **Unidades**: (ej. "Condición Física") ligadas a un periodo.
  - **Sesiones**: (ej. "Sesión de resistencia") ligadas a una unidad con descripción detallada.
- **Visualización**: Actualmente se muestra como una lista anidada (LazyColumn).

### 4. Rúbricas
**Propósito**: Definir criterios de evaluación cualitativos.
- **Estructura**:
  - **Rúbrica**: Nombre general.
  - **Criterios**: (ej. "Técnica", "Puntualidad") con un peso (0.0 a 1.0).
  - **Niveles**: (ej. "Excelente", "Regular") con puntos asociados (ej. 10pts).

### 5. Informes
**Propósito**: Generar documentación oficial.
- **Funcionalidad**: Selección de clase y exportación a PDF. El sistema genera un reporte con medias y pesos automáticamente.

### 6. Backups
**Propósito**: Seguridad de los datos locales (Local-First).
- **Acciones**: Crear copias de seguridad de la base de datos SQLite y restaurar versiones anteriores.

---

## 🛠️ Componentes UI Actuales (Compose Material 3)
La versión técnica actual usa componentes estándar que necesitan ser "elevados" estética y funcionalmente:
- **TabRow**: Selector de pestañas superior.
- **LazyColumn/LazyRow**: Listas infinitas para alumnos y columnas del cuaderno.
- **OutlinedTextField**: Inputs de texto para formularios.
- **MaterialTheme**: Esquema de colores Material 3 (actualmente por defecto).

## 🚀 Oportunidades de Rediseño
1. **Vista de Cuaderno**: Reemplazar la tabla básica por una cuadrícula tipo Excel con scroll horizontal fluido y mejor distinción entre columnas editables y calculadas.
2. **Flujo de Navegación**: Considerar un panel lateral (Side Drawer) en lugar de pestañas superiores para aprovechar el ancho de las pantallas de escritorio.
3. **Hierarchy**: Mejorar la jerarquía visual en Planificación y Rúbricas usando indentación visual o tarjetas anidadas.
4. **Modo Oscuro/Claro**: Implementar un esquema basado en "Glassmorphism" que sea elegante en ambos modos.
