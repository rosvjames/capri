# Funciones de Capri: fichas y criterios

Capri quiere ser un asistente útil de macOS que vive en el notch y ayuda en tareas cotidianas. Su personalidad y su presencia importan, pero su utilidad tiene que justificar usarla todos los días.

Este documento es la referencia común para diseñar e implementar cada función: qué necesita el usuario, qué entra, qué se ve, qué puede fallar y cuándo se da por terminada. Las capacidades y sus IDs (`C-xx`) están en [CAPACIDADES.md](CAPACIDADES.md) y el orden de trabajo, en [ROADMAP.md](ROADMAP.md).

Estado: acordado el 2026-11-03. Las fichas se completan cuando el diseño de cada función esté aprobado.

## Criterios comunes
- Capri comunica lo que de verdad está pasando. Se distinguen seis estados: **escuchando, interpretando, ejecutando, esperando al usuario, completado y falló**.
- No anuncia éxito antes de comprobar el resultado: si abre una app, verifica que se abrió.
- Los resultados se pueden copiar, abrir o usar cuando tiene sentido.
- Lo simple funciona sin el modelo de lenguaje cuando es viable ("pausa", "¿qué hora es?").
- Las acciones se validan en el código; las instrucciones del modelo no bastan.
- Confirmaciones concretas solo cuando la acción lo requiere. Capri muestra comandos, nunca los ejecuta.
- Bajo consumo en reposo: eventos en vez de consultas en bucle, animaciones continuas fuera del proceso de la app.
- Cada función se añade sin rediseñar toda la app.
- Voz primero: lo que basta con oír no abre el panel.

## Estructura del notch (por diseñar)
- **Niveles:** cerrado (información mínima y señales), abierto (contenido y controles de la función elegida) y ampliado (resultados, archivos o detalles que necesitan más espacio). Lo extenso, como ajustes o historiales, puede ir en una ventana aparte.
- **Navegación:** hipótesis inicial, un modelo híbrido con secciones que el usuario elige y avisos temporales. Se compararán dos o tres alternativas antes de decidir.
- **Coincidencias:** hay que definir qué pasa con música y un temporizador a la vez, una conversación mientras trabaja un agente, una decisión pendiente mientras se consulta otra sección y una tarea que termina con el notch cerrado. Regla de partida: ningún cambio automático hace perder la vista elegida ni interrumpe una interacción; los avisos tienen prioridad y duración, y lo pendiente se puede recuperar.
- **Capri:** se conserva cómo se anima y aparece en el notch, pero no tiene por qué ocupar siempre el mismo sitio; cada vista puede tener su propia composición.

## Fichas

### Música (C-29, C-09) — vista nueva hecha en la Fase 5
- **Necesidad:** ver y controlar lo que suena sin cambiar de app. "Pausa", "siguiente", "¿qué suena?", "pon tal canción".
- **Entrada:** avisos de Spotify (canción, artista, álbum, estado, ID, posición y duración); carátula, repetición y posición al abrir por AppleScript; Me gusta, cola y listas por la API web con la sesión de Spotify (PKCE, guardada en el Llavero).
- **Estados:** sin Spotify, en pausa, sonando, cambio de canción. Si Capri escucha o habla, tiene prioridad.
- **Controles hoy:** Me gusta, anterior, pausa/reproducir, siguiente, repetir y saltar con la barra de progreso. Por voz, además de los de la Fase 4: "dale me gusta", "añade X a la cola", "pon mi lista X".
- **Vista:** 440 × 188 pt centrada en la cámara, con Capri recostada en capas (cuerpo detrás de la interfaz, dedos delante del borde) y gestos por eventos: mirada al abrir, parpadeo cada 4–8 s, tamborileo cada 6–12 s solo mientras suena.
- **Errores:** sin permiso de Automatización (no hay carátula ni controles, el resto funciona), Spotify cerrado, carátula no disponible, sin sesión de Spotify (Me gusta, cola y listas piden conectarla).
- **Permisos:** Automatización sobre Spotify, opcional, pedido la primera vez que hace falta.
- **Terminado:** los controles responden, lo que se ve coincide con Spotify y con el notch cerrado el consumo sigue en 0 %.

### Spotify en una burbuja (C-37) — prototipo funcional, Fase 5
- **Necesidad:** elegir qué escuchar (tus listas, tus Me gusta, lo reciente, la cola, una búsqueda) sin cambiar de app ni de escritorio.
- **Entrada:** API web de Spotify con tu sesión; la búsqueda, con la clave de cliente. Desde febrero de 2026 la API no da recomendaciones, Daily Mix, categorías ni las canciones de listas ajenas, y la búsqueda devuelve 10 resultados por tipo como mucho.
- **Interfaz:** botón bajo el panel de música; burbuja aparte de 380 × 460 pt que sí recibe el teclado sin quitarle el foco a la app de delante. Se cierra con Esc, la X, el botón o un clic fuera. Aspecto provisional: el diseño está encargado.
- **Acciones:** tocar reproduce (dentro de la lista abierta, si hay) por la API web, sin traer Spotify al frente; tus listas se abren para ver sus canciones; un botón por fila añade a la cola.
- **Estados:** sin sesión (botón para conectar), cargando (se muestra lo último guardado mientras se actualiza), sin resultados, error, Spotify cerrado.
- **Recursos:** al abrir el panel de música carga por detrás su pestaña (como mucho una vez por minuto); carátulas reducidas a 80 px y guardadas en disco. Cerrada no ocupa memoria.
- **Terminado:** abre al instante, cada acción suena sin cambiar de app y con el uso normal Capri sigue en ~40 MB.

### Acciones locales (C-06 a C-09, C-36) — Fase 4
- **Necesidad:** hacer cosas del Mac por voz sin buscarlas. "¿Qué hora es?", "abre Safari", "abre YouTube", "sube el volumen", "pausa".
- **Entrada:** la frase dictada. Las órdenes comunes se resuelven en el Mac sin el modelo; las abiertas las interpreta el modelo, que elige una herramienta con sus datos (`abrir_app("Safari")`), y la app la ejecuta. Lo que el modelo calcula mal (la hora en otra ciudad) lo calcula el Mac: el modelo solo elige la zona horaria.
- **Estados:** escuchando → interpretando → ejecutando → completado o falló.
- **Resultado:** la acción hecha y comprobada, con una confirmación hablada corta ("Abriendo Safari", "Son las nueve y cuarenta"). En pantalla, como mucho una señal breve.
- **Errores:** app no encontrada ("No encuentro esa app"), dirección no válida, Spotify cerrado, sin internet (la vía local sigue funcionando).
- **Permisos:** ninguno nuevo.
- **Terminado:** "abre Claude", "pon tal canción" y "¿qué hora es?" funcionan por voz, con su latencia medida.

### Temporizadores y recordatorios (C-23)
- **Necesidad:** que Capri avise a tiempo. "Avísame en 25 minutos", "recuérdame llamar a mamá mañana a las nueve".
- **Entrada:** duración o fecha y hora, más un texto. Los temporizadores viven en Capri y sobreviven a reiniciarla; los recordatorios van a la app Recordatorios, así también llegan al iPhone.
- **Estados:** programado, avisando, pospuesto, cancelado, vencido con el notch cerrado.
- **Controles:** temporizadores activos con su tiempo restante, cancelar y posponer.
- **Resultado:** confirmación con la hora exacta ("Te aviso a las 3:25").
- **Errores:** hora ambigua ("a las nueve", ¿de la mañana o de la noche?) → Capri pregunta; permiso de Recordatorios denegado.
- **Permisos:** Recordatorios (EventKit), pedido la primera vez.
- **Terminado:** avisa a tiempo con la app abierta, recupera los temporizadores tras reiniciar y los recordatorios aparecen en Recordatorios.

### Seguimiento de Claude Code y Codex (C-26)
- **Necesidad:** saber, sin mirar la terminal, si un agente sigue trabajando, terminó, falló o espera una respuesta, y volver a esa sesión.
- **Entrada:** eventos de los propios agentes. Claude Code puede avisar al empezar, al pedir permiso o esperar y al terminar, mediante hooks que mandan un mensaje local a Capri. En Codex hay que comprobar qué eventos expone.
- **Estados:** trabajando, esperando respuesta, terminado, error; puede haber varios agentes a la vez.
- **Controles:** abrir la sesión, descartar el aviso. Aprobar permisos desde Capri queda como ampliación posterior.
- **Errores:** hooks sin instalar, Capri cerrada cuando llega un evento, sesión ya cerrada.
- **Permisos:** añadir los hooks a la configuración de los agentes, con el visto bueno del usuario; ninguno de macOS.
- **Terminado:** el aviso llega en menos de un segundo, abrir la sesión funciona y en reposo el consumo es 0 %.

### Texto seleccionado (C-32)
- **Necesidad:** pedir ayuda sobre lo que se está viendo con el menor número de pasos. Seleccionar un error y decir "¿qué significa esto?", "tradúcelo", "resúmelo", "reescríbelo más formal".
- **Entrada:** el texto seleccionado en la app de delante, leído por Accesibilidad. Si la app no lo expone, una copia temporal (⌘C) que deja el portapapeles como estaba. El portapapeles sigue funcionando como hoy.
- **Estados:** sin selección, leyendo, interpretando, resultado.
- **Resultado:** respuesta hablada y, si es texto para usar (traducción, reescritura), copiable. Reemplazar la selección queda como ampliación posterior.
- **Errores:** nada seleccionado, app que no permite leer la selección, texto demasiado largo.
- **Permisos:** Accesibilidad (ya concedida para el ⌘ derecho). Solo se lee cuando la frase lo pide; los campos de contraseña no exponen su texto.
- **Terminado:** funciona en Terminal, el navegador, el editor de código y Notas, y avisa cuando una app no lo permite.

## Siguientes candidatas
Viables, sin orden cerrado: dictado en otras apps (C-33), rutinas con Atajos de Apple (C-34), bandeja de archivos y archivos como contexto (C-35) y memoria persistente que se puede consultar, corregir y olvidar (C-21). Para evaluar más adelante: agenda, notas rápidas, historial del portapapeles, búsqueda web con fuentes, captura de pantalla como contexto (C-22), guía en pantalla (C-31), uso de servicios de IA (C-30), avisos del Mac (C-27), palabra de activación (C-20), proactividad con modo silencio (C-24) y conectores MCP.

Cada candidata se evalúa por frecuencia de uso, pasos que ahorra, fiabilidad, esfuerzo, permisos y consumo.
