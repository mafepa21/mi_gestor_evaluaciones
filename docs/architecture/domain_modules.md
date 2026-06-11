# Domain Modules

La arquitectura de producto se organiza en dos capas: core docente y modulos de dominio.

## Core docente

El core docente es transversal y debe permanecer visible para cualquier perfil de profesor:

- Cuaderno.
- Alumnado.
- Grupos.
- Rubricas.
- Asistencia.
- Planificacion.
- Situaciones.
- Informes.
- Biblioteca.
- Backups/sync.

## Modulos de dominio

Los modulos de dominio amplian el core para necesidades de materia. No deben acoplar la navegacion principal a una sola asignatura.

Educacion Fisica conserva sus capacidades actuales como vertical especializado:

- Sesiones practicas.
- Mediciones y baremos.
- Recursos y material.
- Incidencias y seguridad.
- Retos y torneos.
- Rubricas por area.

Otros perfiles pueden introducir plantillas y flujos propios sin duplicar el Cuaderno ni alterar la logica de evaluacion compartida.

## Regla de implementacion

Primero se generaliza la superficie Apple visible. Despues se conectan asignaturas reales en persistencia. Las entidades fisicas existentes no se renombran ni se eliminan hasta que exista una capa generica consolidada.
