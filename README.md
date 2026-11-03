# Capri

Asistente de voz para macOS con la estética de Capri de *Cyberpunk: Edgerunners 2*. Vive en el notch del MacBook y más adelante también aparecerá en el escritorio.

<p align="center">
  <img src="docs/capturas/notch-abierto-loop.gif" alt="Capri en el notch abierto: mira a un lado, parpadea y se acerca a la pantalla" width="728">
</p>

> 🚧 En desarrollo: Fase 1, identidad visual. Ver el [roadmap](docs/ROADMAP.md).

## Estado actual

Grabaciones y capturas reales de la app en un MacBook Pro de 14" (notch de 185×32 pt).

### Notch abierto
Al pasar el ratón por el notch, el panel se despliega pegado a la cámara y Capri reproduce su loop: mira a un lado, parpadea y se acerca a la pantalla. Son 16 dibujos completos reproducidos con las duraciones aprobadas (31 cambios en 4 s, de 40 a 640 ms cada uno), no una animación interpolada. El título, el mensaje y el botón son interfaz nativa de macOS.

![Notch abierto](docs/capturas/notch-abierto.png)

### Notch cerrado
- **En reposo:** no se dibuja nada; el notch se ve igual que el de la pantalla y la app no consume CPU.
- **Activo** (escuchando o respondiendo): Capri chibi asoma a la izquierda de la cámara y la onda de voz a la derecha.

![Notch cerrado, activo](docs/capturas/notch-activo.png)

### Rendimiento
Medido con la compilación release y `top`:

| Estado | CPU | Memoria |
|---|---|---|
| Notch cerrado, en reposo | 0 % | 13 MB |
| Panel abierto con Capri animada | ~3 % | 26 MB |

## Proceso de diseño

Capri se diseñó por pasos, cada uno aprobado antes de seguir: primero el personaje, luego sus expresiones y una versión simplificada para tamaños pequeños. Después se integró en la app con recortes y tiempos medidos.

| Hoja de personaje | Expresiones | Versión chibi |
|---|---|---|
| ![Hoja de personaje](art/final/A-001-hoja-personaje.png) | ![Expresiones](art/final/A-002-expresiones.png) | ![Chibi](art/final/A-003-hoja-chibi.png) |
| Diseño base, paleta medida sobre la serie | Nueve caras, una por estado | Se reconoce a 32 px, el alto del notch |

## Qué hará
- Conversación por voz con respuestas habladas
- Ayuda con comandos de terminal, revisión de código y explicación de errores
- Acciones locales: abrir apps y sitios, hora y Spotify

Detalle en [docs/CAPACIDADES.md](docs/CAPACIDADES.md).

## Ejecutar

Requiere macOS 14+ y las herramientas de línea de comandos de Xcode. Está pensada para Macs con notch.

```bash
tools/empaquetar.sh --abrir
```

Genera y abre `build/Capri.app`. Para desarrollo rápido, sin permisos de micrófono ni accesibilidad, también se puede ejecutar el binario: `swift build -c release && .build/release/Capri`.

Pasa el ratón por el notch para abrir el panel. Para fijar un estado sin usar el ratón: `open --env CAPRI_ESTADO=abierto build/Capri.app` (o `reposo`, `activo`).

## Stack
Swift, SwiftUI y AppKit con Swift Package Manager. El panel es una ventana transparente sobre la barra de menús, y su geometría se calcula a partir de las medidas reales del notch de cada pantalla.

## Aviso

Fan project no comercial, sin afiliación con CD Projekt Red, Studio Trigger ni Netflix. Capri y *Cyberpunk: Edgerunners* pertenecen a sus respectivos dueños.
