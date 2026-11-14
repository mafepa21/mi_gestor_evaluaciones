# ADR 2026-11-14 · Canal en directo de torneos (iPad → helper → Mac)

## Estado

Aceptado. Rama `codex/torneos-directo-f3` (fase F3 del ticket «Torneos: cuadro visual, fases y modo competición»).

## Contexto

El docente lleva el torneo desde el iPad («Modo directo») y quiere que el Mac lo proyecte al alumnado: pistas, marcadores, reloj y escena, con un retraso de un segundo como mucho. Los resultados ya viajan por SyncLAN, pero con un retraso de 0,5 a 2 s. Además, el reloj vive solo en la vista del iPad.

Guardar el «estado en directo» dentro del plan haría que cada pausa del reloj reescribiera el torneo. También ensuciaría `updatedAt` y la fusión por última modificación con datos que caducan en minutos.

## Decisión

Habrá un canal efímero en el helper del Mac, separado de la sincronización:

- `POST /live/state`: lo usa el iPad enlazado, con el token de sync y TLS anclado. Si el iPad no tiene la huella del Mac, no publica.
- `GET /live/events` (SSE) y `GET /live/state`: solo para la app del Mac, por loopback (la conexión interna del propio Mac) y con su token local.
- El helper valida y reconstruye el JSON solo con los campos del contrato (`v = 1`). Guarda un único estado en memoria durante 30 s y nunca toca la base de datos.
- El iPad manda la hora de fin absoluta del reloj. El helper sella `receivedAtMs` con su reloj y el Mac corrige el desfase entre los dos.
- El iPad envía un latido cada 5 s. Si pasan 12 s sin noticias, el Mac muestra «Sin conexión con el iPad» y conserva la última foto.
- El estado solo lleva identificadores, nunca nombres. La proyección pinta «Equipo N».
- Los resultados definitivos siguen viajando por la sincronización normal. Los marcadores del canal son provisionales y nunca se guardan.
- El Mac abre la proyección solo, sin preguntar (decisión del docente). Al terminar, si el torneo ha acabado, muestra el podio 60 s; si no, se cierra al momento. Una ventana cerrada a mano no se vuelve a abrir en esa sesión.

Contrato completo y trampas: `docs/ambitos/torneos.md` y `docs/ambitos/synclan.md`.

## Alternativas descartadas

- **Estado en el JSON del plan, por la sync normal.** Sale más lento y variable. Ensucia la fusión y deja estados «en directo» colgados si el iPad se apaga.
- **AirPlay del iPad al Mac.** No necesita código, pero depende de AirPlay en la wifi del centro y el Mac no detecta nada.
- **Reutilizar `/sync/events`.** `SyncEventListener` toma cualquier aviso desconocido como «sincroniza ya», lo que dispararía syncs completas en todos los dispositivos.

## Consecuencias

- El helper tiene una lista propia de conexiones (`liveConnections`), y el indicador «iPad conectado» no cambia.
- Un helper antiguo responde 404. El iPad lo interpreta como «Mac sin proyección».
- La apertura automática necesita la ventana principal del Mac abierta.
- Faltan pruebas con dispositivos reales: retraso, wifi con aislamiento entre clientes, iPad en segundo plano, Spaces y relanzar el helper.
