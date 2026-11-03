# Capri

Asistente de voz para macOS con la estética de Capri de *Cyberpunk: Edgerunners 2*. Vive en el notch del MacBook y más adelante también aparecerá en el escritorio.

<p align="center">
  <img src="docs/capturas/notch-abierto-loop.gif" alt="Capri en el notch abierto: mira a un lado, parpadea y se acerca a la pantalla" width="728">
</p>

> 🚧 En desarrollo. Listas: identidad visual, bucle de voz y música en el notch. Siguiente: la IA. Ver el [roadmap](docs/ROADMAP.md).

## Estado actual

Capturas de la app en un MacBook Pro de 14" (notch de 185×32 pt).

### Notch abierto
Al pasar el ratón por el notch, el panel se despliega pegado a la cámara y Capri reproduce su loop: mira a un lado, parpadea y se acerca a la pantalla. Son 16 dibujos completos reproducidos con las duraciones aprobadas (31 cambios en 4 s, de 40 a 640 ms cada uno), no una animación interpolada. El título, el mensaje y el botón son interfaz nativa de macOS.

![Notch abierto](docs/capturas/notch-abierto.png)

### Hablar con Capri
Mantén el ⌘ derecho, habla y suelta (o usa el botón Hablar). Mientras escucha, el notch sigue cerrado con Capri chibi a un lado de la cámara y la onda de tu voz al otro. Al responder, el panel se despliega y Capri habla moviendo la boca al ritmo de lo que se oye. Esc la calla, y en pantalla completa se oculta pero sigue atendiendo al atajo.

- **Escucha** en el propio Mac: reconocimiento de voz de macOS en español de México, sin enviar el audio fuera.
- **Responde** con una voz local provisional (Qwen3-TTS, generada en el Mac), con Paulina, la voz del sistema, como respaldo. La voz definitiva está en exploración.
- Por ahora no entiende lo que le pides: saluda si le dices "hola, Capri" y repite el resto. La IA llega en la siguiente fase.

![Notch cerrado, activo](docs/capturas/notch-activo.png)

### Música en el notch
Con Spotify sonando, el notch cerrado muestra la carátula a un lado de la cámara y unas barras al otro. Al abrir el panel, la canción, el artista y los controles (anterior, pausa, siguiente) ocupan el sitio de la interfaz de Capri, sin mover su dibujo. La app se entera de cada cambio por los avisos que publica Spotify, sin consultarlo en bucle. Para la carátula y los controles pide permiso de Automatización sobre Spotify la primera vez que hace falta. Sin ese permiso, todo lo demás funciona igual.

| Notch cerrado | Panel abierto |
|---|---|
| ![Notch cerrado con música](docs/capturas/musica-cerrado.png) | ![Panel abierto con música](docs/capturas/musica-panel.png) |

<sub>Estas dos capturas las genera la propia app (`--snapshot … musica`) con una canción y una carátula de prueba.</sub>

### Rendimiento
Medido con la compilación release y `top`:

| Estado | CPU |
|---|---|
| Notch cerrado, en reposo | 0 % |
| Notch cerrado con música (las barras las anima el servidor de ventanas) | 0 % |
| Panel abierto con Capri animada | ~3 % |
| Escuchando o respondiendo, con el notch cerrado | ~7 % |

La app ocupa unos 70 MB de memoria. La voz local corre en un proceso aparte: se carga la primera vez que le hablas, en lo que tardas en decir la frase, y ocupa ~4 GB mientras la app sigue abierta.

## Proceso de diseño

Capri se diseñó por pasos, cada uno aprobado antes de seguir: primero el personaje, luego sus expresiones y una versión simplificada para tamaños pequeños. Después se integró en la app con recortes y tiempos medidos.

| Hoja de personaje | Expresiones | Versión chibi |
|---|---|---|
| ![Hoja de personaje](art/final/A-001-hoja-personaje.png) | ![Expresiones](art/final/A-002-expresiones.png) | ![Chibi](art/final/A-003-hoja-chibi.png) |
| Diseño base, paleta medida sobre la serie | Nueve caras, una por estado | Se reconoce a 32 px, el alto del notch |

## Qué hará
- Conversación por voz con respuestas habladas
- Ayuda con comandos de terminal, revisión de código y explicación de errores
- Acciones locales: abrir apps y sitios, hora y pedirle música a Spotify

Detalle en [docs/CAPACIDADES.md](docs/CAPACIDADES.md).

## Ejecutar

Requiere macOS 14+ y las herramientas de línea de comandos de Xcode. Está pensada para Macs con notch.

```bash
tools/empaquetar.sh --abrir
```

Genera y abre `build/Capri.app`. macOS solo concede micrófono, reconocimiento de voz y accesibilidad (para el ⌘ derecho) a la app empaquetada. Si falta alguno, el punto del panel se pone rojo y el botón pasa a **Permisos**. Para desarrollo rápido de la interfaz, sin esos permisos, también se puede ejecutar el binario: `swift build -c release && .build/release/Capri`.

Pasa el ratón por el notch para abrir el panel. Variables útiles:

| Variable | Qué hace |
|---|---|
| `CAPRI_ESTADO=reposo\|activo\|abierto` | Fija un estado e ignora el ratón (para medir rendimiento) |
| `CAPRI_DECIR="texto"` | Capri dice ese texto al arrancar, sin micrófono |
| `CAPRI_TTS=paulina` | Usa la voz del sistema |

La voz local necesita un entorno de Python con [mlx-audio](https://github.com/Blaizzy/mlx-audio) en `~/.venvs/capri-tts` y una referencia de voz que no se incluye en el repositorio. Sin ellos, Capri habla con Paulina (es-MX). Para la mejor calidad, descarga Paulina mejorada en Ajustes del Sistema → Accesibilidad → Contenido leído.

## Stack
Swift, SwiftUI y AppKit con Swift Package Manager. El panel es una ventana transparente sobre la barra de menús, y su geometría se calcula a partir de las medidas reales del notch de cada pantalla. La voz usa Speech y AVAudioEngine; la voz local, un proceso de Python con mlx-audio; la música, los avisos distribuidos de Spotify y AppleScript.

## Aviso

Fan project no comercial, sin afiliación con CD Projekt Red, Studio Trigger ni Netflix. Capri y *Cyberpunk: Edgerunners* pertenecen a sus respectivos dueños.
