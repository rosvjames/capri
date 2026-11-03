# Roadmap

Fases en orden. Cada fase termina con algo que se puede probar y con su estado actualizado aquí.
Estados: ⬜ pendiente · 🟨 en curso · ✅ hecha

## Fase 0 — Base del proyecto ✅
- ✅ Paquete Swift que compila sin Xcode (`swift build`)
- ✅ Prototipo visual del notch con estados simulados (C-02, provisional)
- ✅ Documentación: capacidades, roadmap, estética, convenciones
- ✅ Repositorio en GitHub y primer push ([rosvjames/capri](https://github.com/rosvjames/capri))
- ✅ Cerrar decisiones D-1 a D-6 (`docs/CAPACIDADES.md`)
- ✅ Análisis de otros proyectos de Capri (`docs/REFERENCIAS.md`)

## Fase 1 — Identidad visual ✅ (`v0.1.0`)
Rama: `fase-1/identidad-visual`, fusionada en `main`.
- ✅ Estilo decidido: anime (maestra) + chibi (derivada)
- ✅ Capturas de referencia (A-000); rasgos y paleta confirmados
- ✅ Hoja de personaje de Capri (A-001, referencia maestra)
- ✅ Expresiones (A-002)
- ✅ Hoja chibi (A-003); se reconoce a 32 px
- ✅ Arquitectura visual por capas: bases en imagen, ojos/bocas/efectos por código
- ✅ Base chibi sin rasgos (A-004) + anclajes de ojos y boca
- ✅ Ojos y bocas vectoriales en SwiftUI, replicando las 9 expresiones de A-002 (`CapriFace.swift`)
- ✅ Integrar Capri chibi en el notch y reemplazar el núcleo placeholder
- ✅ Paleta de interfaz de Capri (sin cian)
- ✅ Tipografía de interfaz: fuente del sistema, calibrada contra la maqueta
- ✅ Icono de la barra de menús por código: máscara, ojos de anillo y puntas de melena (`MenuBarIcon.swift`)
- ✅ Panel abierto con el prototipo aprobado v3: fotogramas completos con sus duraciones e interfaz nativa (`NotchPresence.swift`, `art/final/notch-fiel-v3/`)
- ~~Base anime sin rasgos (A-005)~~: sustituida por los fotogramas completos
- ➡️ Notch cerrado con fotogramas: pasa a la Fase 2, donde existen sus estados
- ✅ Hito: el notch muestra a Capri (loop aprobado al abrirlo; cara chibi según el estado al estar cerrado y activo), con 0 % de CPU en reposo

## Fase 2 — Bucle de voz (C-01) 🟨
Rama: `fase-2/voz`. Decisiones: ⌘ derecho mantenido (D-2), español de México (D-8), voz del sistema (D-5).

1. ✅ **App empaquetada** (`Capri.app`, script en `tools/`): macOS solo concede micrófono, reconocimiento de voz y accesibilidad a una app con `Info.plist` y firma. Lanzada como binario suelto, los permisos se atribuirían a la terminal.
   - ✅ `tools/empaquetar.sh [--abrir]` genera y firma `build/Capri.app` (`Info.plist` en `app/`).
   - ✅ Firma estable con el certificado propio "Capri Dev": la identidad de la app (identificador + certificado) no cambia entre compilaciones, así que los permisos se conservan.
2. ✅ **Permisos** (`Permissions.swift`): si falta alguno, el punto del panel se pone rojo y el botón pasa a **Permisos**, que los pide en orden (micrófono → voz → accesibilidad) o abre el ajuste correcto si ya se denegaron. La accesibilidad se detecta en vivo. Probado en la app empaquetada; los permisos se conservan al recompilar.
3. ✅ **Atajo ⌘ derecho** (`PushToTalk.swift`): mantenerlo ~0,25 s solo, sin otra tecla, empieza a escuchar; soltarlo termina. Un toque corto no hace nada; si se pulsa otra tecla o modificador mientras se mantiene, se cancela. Los monitores se instalan al conceder accesibilidad. Por ahora solo cambia el estado del notch a "escuchando".
4. ✅ **Escuchar** (`SpeechListener.swift`): micrófono + reconocimiento `es-MX` en el propio Mac (sin enviar audio fuera). La frase aparece en vivo en el panel (dos líneas, mostrando el final) y la onda del notch cerrado sigue el nivel real del micrófono. El botón Hablar empieza y termina la escucha. Se añaden los signos de apertura ¿ ¡.
5. ✅ **Responder en voz** (`Speaker.swift`): Paulina (es-MX), elegida escuchando las voces; se usa automáticamente su mejor calidad instalada; hoy, Paulina mejorada (Enhanced), descargada en Ajustes del Sistema → Accesibilidad → Contenido leído. En esta fase, eco: "Entendí: …" o "No te escuché.". Hablarle mientras responde la calla.
6. 🟨 **Estados del notch conectados al flujo real**: reposo → escuchando (notch cerrado, chibi) → procesando → respondiendo (el notch se despliega y Capri habla en el panel) → reposo (se cierra). La franja de texto pasa a la Fase 3.
   - ✅ Estados con el notch cerrado
   - ⬜ Desplegar el panel mientras responde y cerrarlo al terminar
7. ✅ **C-10**: Esc la calla o cancela la escucha (macOS también entrega el Esc a la app de delante). En pantalla completa Capri se oculta y sigue respondiendo al ⌘ derecho (`FullscreenWatcher.swift`: tipo de escritorio activo, sin consultar en bucle). El modo silencio pasa a C-24: hoy Capri solo habla cuando se lo pides.
8. 🟨 **Capri hablando en el panel**: dos bocas nuevas (entreabierta y abierta) sobre el fotograma v3 en reposo, como en la serie. Al responder, la boca cambia a saltos siguiendo las palabras de la voz, con parpadeos de vez en cuando. La escucha conserva la chibi actual del notch cerrado.
- Hito: mantienes ⌘ derecho, dices una frase, sueltas, y Capri la muestra y responde en voz "Entendí: …". En reposo sigue a 0 % de CPU.

## Fase 2b — Música en el notch (C-29)
Justo después de la voz: da vida al notch sin depender de la IA.
- ⬜ Leer la canción actual de Spotify por sus avisos de cambio (sin sondeo)
- ⬜ Notch cerrado: carátula y barras mientras suena música
- ⬜ Panel: canción, artista y controles (anterior, pausa, siguiente)
- ⬜ Volver a Capri cuando no hay música o tras el aviso de cambio de canción
- Hito: al cambiar de canción el notch la muestra, y en reposo sigue a 0 % de CPU

## Fase 3 — Cerebro (C-03, C-04, C-05)
- ⬜ Cliente LLM detrás de un protocolo (para cambiar proveedor)
- ⬜ Personalidad de Capri (prompt de sistema)
- ⬜ Franja inferior del panel para lo que hay que leer o copiar (comandos, código, enlaces): se abre al terminar de hablar, con botón de copiar, y se cierra sola. Las respuestas solo habladas no abren el panel ("voz primero")
- ⬜ Contexto de código: portapapeles y archivo arrastrado al notch
- Hito: preguntas de terminal y de errores respondidas por voz

## Fase 4 — Acciones locales (C-06 a C-09)
- ⬜ Tool calling: el LLM elige herramienta, la app la ejecuta
- ⬜ Hora/fecha, abrir apps, abrir sitios
- ⬜ Control de música
- Hito: "abre Claude", "pon tal canción", "¿qué hora es?" funcionan

## Fase 5 — Producto
- ⬜ Empaquetar como `.app` con icono, que se inicie con la sesión
- ⬜ Ajustes (API key en Llavero, atajo, voz)
- ⬜ Abrir ajustes y salir desde el panel: si la barra de menús está llena, macOS esconde el icono de Capri detrás del notch
- ⬜ README con GIF/video de demo, diagrama de arquitectura
- ⬜ Release v1.0

## Fase 6+ — Extras
Capacidades C-20 en adelante, según interés. Candidata destacada: C-30, uso de IA en el notch.
