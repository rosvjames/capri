# Proyectos de referencia

Análisis de los proyectos de Capri en GitHub (revisados el 2026-11-01) para decidir qué ideas traer.
Solo se toman **ideas**: no se copia código, arte ni voces de estos repos (varios tienen licencias no comerciales o arte con derechos de terceros).

## Proyectos revisados

| Proyecto | ★ | Plataforma / stack | Enfoque |
|---|---|---|---|
| [mochiiwuff/capri-desktop](https://github.com/mochiiwuff/capri-desktop) | 484 | Windows · JavaScript | Narra lo que hacen Claude Code / Codex mientras trabajan; animación muy elaborada |
| [lachydotmcg/capri-desktop](https://github.com/lachydotmcg/capri-desktop) | 266 | Windows (Mac/Linux preview) · C# | Compañera completa: voz, "Hey Capri", acciones, memoria, mini reproductor. Licencia PolyForm Noncommercial |
| [TheAgencyMGE/capri-companion](https://github.com/TheAgencyMGE/capri-companion) | 26 | Windows · Electron/TS | Compañera con teletransporte glitch, acciones con aprobación, recordatorios. Código MIT |
| [X1a0heZzzz/capri-desktop-pet](https://github.com/X1a0heZzzz/capri-desktop-pet) | 15 | Paquete de sprites | Solo arte: 9 animaciones en atlas para hosts de mascotas |
| [4lexxe/capri_cyberpunk_MOBILE](https://github.com/4lexxe/capri_cyberpunk_MOBILE) | 5 | Android · Kotlin | Versión móvil en español latino, TTS local |
| [spiermar2/capri-for-mac](https://github.com/spiermar2/capri-for-mac) | 3 | macOS 26 · Swift | La más cercana a nuestro stack: estrella compacta que se abre en ventana, voz ElevenLabs |
| [Spectro34/capri-mate](https://github.com/Spectro34/capri-mate) | 2 | Linux · Python/GTK4 | Sprites rigueados en Blender a partir de frames de la serie. Código MIT |
| [CyberMoonie/capri-macos](https://github.com/CyberMoonie/capri-macos) | 0 | macOS · JavaScript | Port a Mac de mochiiwuff; integra Spotify, Spotlight, sensores del Mac |
| [ACE07X/CapriCompanion](https://github.com/ACE07X/CapriCompanion) | 0 | Windows · Python | 100 % local (Ollama, Vosk, Kokoro); modelo de seguridad muy cuidado |
| [glitchy-z/capri-bot](https://github.com/glitchy-z/capri-bot) | 0 | Bot de WhatsApp · Node | Persona de Capri en chat, no es app de escritorio |

### ⚠️ Repo sospechoso: no descargar
[capridotcom/Capri-AI](https://github.com/capridotcom/Capri-AI) (91★) tiene señales típicas de malware disfrazado:
- su README copia textualmente el de lachydotmcg
- el `.exe` se descarga desde **otra cuenta distinta** (`Watchacrossknot36`)
- la cuenta tiene un único repo

Es probable que use el tirón de Capri para distribuir un ejecutable malicioso.

## Qué nos diferencia
- **Ninguno usa el notch.** Es la innovación del proyecto.
- Solo dos funcionan en Mac, y ninguno es una app nativa centrada en asistencia técnica (terminal, código, errores).
- Pensado en español desde el inicio.

## Evaluación de funcionalidades

### ✅ Traer (encaja en v1)

| Idea | Visto en | Dónde entra |
|---|---|---|
| Push-to-talk con atajo global | Todos | C-01 · Fase 2. Idea para Mac: un toque de la tecla ⌘ derecha (capri-for-mac) |
| **Esc para callarla o cancelar** | lachy, TheAgency, ACE07X | C-10 nueva · Fase 2 |
| **Modo silencio y ocultarse en pantalla completa** | lachy, TheAgency, Spectro34 | C-10 · Fase 2 |
| Spotify por AppleScript: reproducir por nombre, pausar, "¿qué suena?" | lachy, CyberMoonie, ACE07X | C-09 · Fase 4 |
| Pedir confirmación antes de acciones sensibles | TheAgency, ACE07X, Capri-AI | Principio general · Fase 4 |
| Proveedor de LLM intercambiable | Todos | D-1 · Fase 3 |
| Claves de API en el Llavero de macOS | capri-for-mac | Fase 5 |
| Si falta un permiso, decir cuál y abrir el ajuste correcto de Sistema | CyberMoonie | Fase 2 y 4 |

### 🟨 Considerar para v2

| Idea | Visto en | Comentario |
|---|---|---|
| **Narrar lo que hace Claude Code** (vía hooks): `EDITA gigs.ts`, `EJECUTA npm test`, avisar cuando pide permiso o termina | mochiiwuff (el más popular), CyberMoonie | **Candidata fuerte** (C-26): el notch es el lugar ideal para ese "ticker" y encaja con tu uso diario |
| Presencia en el escritorio: sentarse en ventanas, asomarse por los bordes, teletransporte glitch | Casi todos | C-25 / D-7 |
| Reacciones en espera sin gastar IA (miradas, gestos) | capri-for-mac, Spectro34 | C-28; encaja con la Fase 1 |
| Reaccionar al Mac: cargador, batería, AirPods, CPU al máximo | CyberMoonie | C-27; barato en macOS y le da vida |
| "Hey Capri" | lachy | Ya está como C-20 |
| Memoria local de conversaciones | lachy, ACE07X | Ya está como C-21 |
| Ver la pantalla con permiso | lachy, ACE07X, TheAgency | Ya está como C-22 |
| Temporizadores, recordatorios, notas | TheAgency, ACE07X | Ya está como C-23 |
| Voz con carácter mediante Voice Design de ElevenLabs (describir la voz, sin clonar) | lachy, capri-for-mac | D-5, después de v1 |

### ❌ No traer

| Idea | Visto en | Por qué |
|---|---|---|
| Que controle el ratón y el teclado sola | lachy, TheAgency | Complejo, frágil y riesgoso; fuera del propósito |
| Explorar la web sola cuando no estás | TheAgency | Riesgo de seguridad sin beneficio claro |
| Jugar o comentar juegos | lachy | Fuera del propósito |
| Celos de otras IAs y nivel de apego | CyberMoonie | Gracioso, pero obliga a vigilar ventanas y pestañas |
| Sprites sacados de frames de la serie | Spectro34, X1a0heZzzz | Arte con derechos de terceros |
| Bot de WhatsApp, descargas de video | glitchy-z | Es otro producto |

## Lecciones técnicas útiles
- **Ritmo de anime** (Spectro34): la serie la anima a unos 3 dibujos por segundo, con poses que *saltan* en vez de interpolarse suavemente. Respalda animar con pocos dibujos bien elegidos y tiempos marcados, sin necesidad de muchos frames.
- **Acciones locales sin IA** (TheAgency): abrir apps, temporizadores y notas funcionan aunque no haya LLM. Lo aplicamos en C-06 a C-09.
- **Seguridad de herramientas** (ACE07X): las acciones se validan en el código, no solo en el prompt; comandos de una lista permitida y aprobación de un solo uso.
- **Distribución en Mac** (capri-for-mac, CyberMoonie): sin Developer ID, macOS bloquea la app y hay que explicar "Abrir de todos modos". Tenerlo en cuenta en la Fase 5.
