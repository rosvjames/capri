# Capacidades de Capri

Asistente de escritorio para macOS con la estética de Capri (*Cyberpunk: Edgerunners 2*), que se usa principalmente por voz.

El notch es su primera superficie y una de las funciones distintivas del proyecto, pero no la única: más adelante Capri también aparecerá en el escritorio e interactuará con la pantalla (C-25).

Cada capacidad tiene un ID (`C-xx`) que se usa en el roadmap, en issues y en los commits.

## Núcleo (v1)

| ID | Capacidad | Ejemplos | Cómo se resuelve |
|---|---|---|---|
| C-01 | Conversación por voz | Hablarle y que responda en voz alta | Activación → reconocimiento de voz → LLM → síntesis de voz |
| C-02 | Presencia en el notch | Ver su estado: en espera, escuchando, pensando, respondiendo | Panel SwiftUI sobre el notch con la estética de Capri |
| C-03 | Preguntas de terminal | "¿Cuál es el comando para listar puertos abiertos?" | LLM; la respuesta se muestra copiable en el panel además de decirse en voz |
| C-04 | Dudas rápidas de código | "¿Qué hace este comando?" (no es revisión a fondo: para eso están Claude y Codex) | LLM + contexto: portapapeles; archivo arrastrado al notch, más adelante |
| C-05 | Explicar errores | "¿Por qué me da este error?" | Igual que C-04, con el mensaje de error como contexto |
| C-06 | Hora y fecha | "¿Qué hora es?" | Local, sin LLM |
| C-07 | Abrir aplicaciones | "Abre Safari", "abre Claude", "abre ChatGPT" | Local (`NSWorkspace`); el LLM solo identifica la intención |
| C-08 | Abrir sitios | "Abre YouTube" | Local; abre la URL en el navegador por defecto |
| C-09 | Música (Spotify) | "Pon tal canción", "pausa", "¿qué suena?" | AppleScript sobre Spotify |
| C-10 | Interrumpir y silenciar | Esc la calla o cancela; modo silencio; se oculta en pantalla completa | Local |
| C-23 | Temporizadores y recordatorios | "Avísame en 25 minutos", "recuérdame llamar mañana a las nueve" | Temporizadores locales persistentes; recordatorios en la app Recordatorios (EventKit) |
| C-26 | Seguimiento de Claude Code y Codex | Avisar cuando un agente termina, falla o espera una respuesta, y volver a su sesión | Hooks de los agentes que avisan a Capri por un canal local, sin consultar en bucle |
| C-32 | Ayuda con el texto seleccionado | Seleccionar un error y decir "¿qué significa esto?", "tradúcelo", "resúmelo" | Accesibilidad (selección de la app de delante), con copia temporal como alternativa; resultado copiable |
| C-36 | Volumen del Mac | "Sube el volumen", "silencio" | Local, sin LLM en las órdenes comunes |
| C-29 | Música en el notch | Notch cerrado: carátula a un lado y barras al otro mientras suena algo. Panel: carátula, canción, artista y controles en el sitio de la interfaz de Capri, sin cambiar el tamaño del panel | Avisos de Spotify al cambiar de canción (sin consultar en bucle: 0 % de CPU en reposo) + AppleScript para los controles |
| C-37 | Spotify en una burbuja | Un botón bajo el panel de música abre una burbuja con tus listas, Tus me gusta, lo último que sonó, la cola y una búsqueda, sin cambiar de app | API web de Spotify con la sesión del usuario (PKCE); lo elegido suena en la app de Spotify por AppleScript |

### Principio de diseño
Lo que se puede resolver localmente (hora, abrir apps, música) **no pasa por el LLM para ejecutarse**: el LLM solo decide *qué* herramienta usar (tool calling). Así es rápido, barato y predecible.

### Voz primero
Capri responde siempre en voz. Mientras escucha, el notch sigue cerrado con su versión chibi junto a la cámara. Cuando responde, el notch se despliega y se la ve hablándote de frente, moviendo la boca; al terminar se vuelve a cerrar. El notch no es un chat: no muestra historial ni repite tu frase. Solo muestra texto cuando oírlo no basta (comandos de terminal, código, enlaces, rutas, datos que vas a usar): una franja inferior con ese contenido y un botón para copiarlo. Lo que entendió solo se ve, discreto, si abres el panel tú.

### Capri es la protagonista del notch
La información extra (música, uso de IA…) aparece cuando es relevante, por ejemplo al cambiar de canción, y después devuelve el panel a Capri. Va en la columna izquierda del panel o a los lados del notch cerrado, sin tocar el recorte de Capri. Si hace falta espacio, el panel se ensancha hacia la izquierda; sus fotogramas no cambian. La fecha y la hora no se muestran: la barra de menús ya tiene reloj.

## Después (v2+, no comprometido)

- C-20 Palabra de activación ("Capri") en vez de atajo de teclado
- C-21 Memoria persistente explícita: recordar preferencias y decisiones, que el usuario pueda consultar, corregir y olvidar
- C-22 Leer la ventana activa (captura de pantalla) como contexto de código
- C-24 Comentarios espontáneos / personalidad proactiva, con un modo silencio para desactivarlos
- C-25 Presencia en el escritorio: aparecer fuera del notch, moverse e interactuar con la pantalla (D-7)
- C-27 Reaccionar al Mac: cargador, batería, AirPods, CPU al máximo
- C-28 Reacciones en espera sin gastar IA (miradas, gestos)
- C-30 Uso de IA en el notch: consumo, créditos o límites de cada servicio (Claude, ChatGPT…). Cada servicio lo expone distinto (API con clave de administrador, archivos locales), así que se evalúa servicio por servicio
- C-31 Guía en pantalla: Capri sale del notch y señala dónde hacer clic para llegar a lo que pides ("¿cómo reinicio?"). Depende de C-22 (ver la pantalla) y C-25 (moverse fuera del notch)
- C-33 Dictado en otras apps: hablar para escribir donde esté el cursor (otro atajo, distinto del de conversar)
- C-34 Rutinas: "modo trabajo" abre apps y el proyecto, ejecuta un Atajo de Apple e inicia un temporizador
- C-35 Bandeja de archivos: arrastrarlos al notch para tenerlos a mano o preguntar por ellos ("¿por qué falla este log?")

Origen de C-10 y C-25 a C-28: análisis de otros proyectos en `docs/REFERENCIAS.md`. Origen de C-32 a C-36 y de la ampliación de C-21, C-23 y C-26: segunda revisión de proyectos del 2026-11-03 (fichas en `docs/FUNCIONES.md`).

## Decisiones

### Cerradas (2026-11-01)

| # | Pregunta | Decisión |
|---|---|---|
| D-1 | ¿Qué LLM? | **Claude por API**, detrás de un protocolo (revisado 2026-11-04). El modelo local (Gemma 4 12B con Ollama) funcionaba, pero ocupaba 10–17 GB de RAM junto a la voz y el Mac mandaba memoria al disco; Capri convive con muchas apps abiertas. Hoy, Haiku 4.5 por el AI Gateway de Astropods (créditos sobrantes, clave de 24 h); a la larga, clave propia de Anthropic con Haiku 5.5 (~US$0,25/mes), con un tope de ~US$5/mes. Gemma queda como opción sin internet. Capri es para preguntas rápidas, no para trabajo de código a fondo |
| D-2 | ¿Cómo se activa? | **⌘ derecho mantenido** (push-to-talk): hablas mientras lo mantienes y al soltar Capri responde. También el botón Hablar del panel. Palabra de activación en v2 (C-20). Decidido 2026-11-02 |
| D-3 | ¿Qué app de música? | Spotify |
| D-4 | ¿Reconocimiento de voz? | Speech de Apple (nativo, gratis) en v1 |
| D-5 | ¿Voz de respuesta? | Voz del sistema en v1: **Paulina (es-MX)** en su mejor calidad instalada (hoy, la mejorada / Enhanced). Voz con más carácter después (ElevenLabs Voice Design o TTS local tipo Kokoro) |
| D-6 | ¿Repositorio público? | Público, con aviso de fan project no comercial |
| D-8 | ¿Qué español? | México / Latinoamérica: reconocimiento `es-MX` y voz del sistema `es_MX` (decidido 2026-11-02) |

### Abiertas

| # | Pregunta | Notas |
|---|---|---|
| D-7 | ¿Cuándo y cómo aparece Capri en el escritorio, fuera del notch? | Ver C-25. Se decide cuando el notch y la voz funcionen |
