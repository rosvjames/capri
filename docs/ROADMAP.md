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

## Fase 2 — Bucle de voz (C-01) ✅ (`v0.2.0`)
Rama: `fase-2/voz`, fusionada en `main`. Decisiones: ⌘ derecho mantenido (D-2), español de México (D-8), voz del sistema (D-5).

1. ✅ **App empaquetada** (`Capri.app`, script en `tools/`): macOS solo concede micrófono, reconocimiento de voz y accesibilidad a una app con `Info.plist` y firma. Lanzada como binario suelto, los permisos se atribuirían a la terminal.
   - ✅ `tools/empaquetar.sh [--abrir]` genera y firma `build/Capri.app` (`Info.plist` en `app/`).
   - ✅ Firma estable con el certificado propio "Capri Dev": la identidad de la app (identificador + certificado) no cambia entre compilaciones, así que los permisos se conservan.
2. ✅ **Permisos** (`Permissions.swift`): si falta alguno, el punto del panel se pone rojo y el botón pasa a **Permisos**, que los pide en orden (micrófono → voz → accesibilidad) o abre el ajuste correcto si ya se denegaron. La accesibilidad se detecta en vivo. Probado en la app empaquetada; los permisos se conservan al recompilar.
3. ✅ **Atajo ⌘ derecho** (`PushToTalk.swift`): mantenerlo ~0,25 s solo, sin otra tecla, empieza a escuchar; soltarlo termina. Un toque corto no hace nada; si se pulsa otra tecla o modificador mientras se mantiene, se cancela. Los monitores se instalan al conceder accesibilidad. Por ahora solo cambia el estado del notch a "escuchando".
4. ✅ **Escuchar** (`SpeechListener.swift`): micrófono + reconocimiento `es-MX` en el propio Mac (sin enviar audio fuera). La frase aparece en vivo en el panel (dos líneas, mostrando el final) y la onda del notch cerrado sigue el nivel real del micrófono. El botón Hablar empieza y termina la escucha. Se añaden los signos de apertura ¿ ¡.
5. ✅ **Responder en voz** (`Speaker.swift`): Paulina (es-MX), elegida escuchando las voces; se usa automáticamente su mejor calidad instalada; hoy, Paulina mejorada (Enhanced), descargada en Ajustes del Sistema → Accesibilidad → Contenido leído. En esta fase, eco: "Entendí: …" o "No te escuché.". Hablarle mientras responde la calla.
6. ✅ **Estados del notch conectados al flujo real**: reposo → escuchando (notch cerrado, chibi) → procesando → respondiendo (el notch se despliega y Capri habla en el panel) → reposo (se cierra 1,5 s después, salvo con el ratón encima). Abierto así, no muestra lo que dictaste. La franja de texto pasa a la Fase 3.
7. ✅ **C-10**: Esc la calla o cancela la escucha (macOS también entrega el Esc a la app de delante). En pantalla completa Capri se oculta y sigue respondiendo al ⌘ derecho (`FullscreenWatcher.swift`: tipo de escritorio activo, sin consultar en bucle). El modo silencio pasa a C-24: hoy Capri solo habla cuando se lo pides.
8. ✅ **Capri hablando en el panel** (`TalkingFace.swift`): 12 fotogramas (3 bocas × 4 estados de ojos) sobre la pose de reposo del v3. La boca sigue el volumen de la voz que se está oyendo, medido cada 20 ms y sincronizado con la reproducción (`Speaker.swift` reproduce el audio él mismo); cambia a saltos, con al menos 90 ms por dibujo. Parpadea cada 4–8 s. La escucha conserva la chibi del notch cerrado.
9. ✅ **Voz local provisional** (`LocalQwen.swift`, `Resources/qwen-speaker.py`): Qwen3-TTS en el propio Mac clona una referencia de voz que no está en el repo (`capri-qwen-ref2.wav` y su transcripción `.txt`); sin ella, `CAPRI_TTS=paulina`. El modelo se precarga al empezar a escuchar: una respuesta corta suena a ~1,7 s en vez de ~3,7 s. El audio se limpia con RNNoise y el motor de audio se apaga 3 s después de hablar (0 % en reposo). `CAPRI_DECIR="texto"` la hace hablar sin micrófono. La voz definitiva sigue pendiente.
- ✅ Hito: mantienes ⌘ derecho, dices una frase, sueltas, y el notch se despliega con Capri respondiéndote en voz y moviendo la boca. En reposo sigue a 0 % de CPU.

## Fase 2b — Música en el notch (C-29) 🟨
Rama: `fase-2b/musica`. Solo Spotify. Decisiones: notch cerrado con carátula y barras (no el ojo de Capri), barras con animación ligera solo mientras suena, panel sin barra de progreso ni volumen.

1. ✅ **Leer Spotify** (`MusicWatcher.swift` → `model.nowPlaying`): el aviso `com.spotify.client.PlaybackStateChanged` (canción, artista, álbum, estado, ID) llega en cada cambio, sin consultar en bucle. Hay que pedirlo con entrega inmediata: Capri nunca es la app activa y macOS retendría los avisos. Al cerrar Spotify llega `Stopped` y además se vigila su cierre. Probado con pausa, reanudar, siguiente y cerrar; 0 % de CPU en reposo.
2. ✅ **Permiso de Automatización** sobre Spotify (`SpotifyAutomation` en `Permissions.swift`, `SpotifyRemote.swift`): es opcional, así que no entra en la lista de permisos que pone el punto en rojo ni bloquea el ⌘ derecho. Se pide la primera vez que hace falta la carátula, nunca al arrancar; si se revoca en Ajustes se detecta en el siguiente script. Con el permiso, al abrir Capri se lee lo que ya sonaba. Los scripts corren en su propia cola y comprueban dentro que Spotify siga abierto, para no abrirlo. Probado en la app empaquetada.
3. ✅ **Carátula** (`ArtworkCache.swift` → `model.artwork`): al cambiar de canción se busca en la caché (`~/Library/Caches/com.rosvjames.capri/caratulas`, por ID, 160 px, se conservan 500) y, si no está, se pide `artwork url` a Spotify, se descarga una vez y se reduce. Solo se acepta si Spotify sigue en esa canción; si no se consigue, se reintenta en el siguiente aviso. Probado: descarga en ~0,7 s, caché en ~2 ms.
4. ✅ **Notch cerrado** (`NotchView.swift`, `MusicBars` y `ArtworkThumb` en `Visuals.swift`): mientras suena y Capri está en reposo, el notch se ensancha con la carátula a la izquierda y barras verdes a la derecha, sin el borde rojo de Capri activa. Si Capri escucha o habla, gana ella; en pausa vuelve al notch de la pantalla. Las barras no siguen el audio: las anima Core Animation en el servidor de ventanas, así que la app no dibuja cuadros (con una animación de SwiftUI, cada cuadro redibujaba el panel: ~5 % a 10 fps). Medido con el notch visible: 0 % de CPU con música. `--snapshot … colapsado musica` lo captura con una carátula sintética.
5. ⬜ **Panel**: en la columna izquierda, sin tocar el recorte de Capri, carátula, canción, artista y controles (anterior, pausa, siguiente) por AppleScript.
6. ⬜ **Convivencia**: al cambiar de canción el panel la muestra unos segundos y vuelve a Capri. En pausa o sin Spotify, el notch vuelve a su estado normal.
- Hito: al cambiar de canción el notch la muestra; los controles funcionan; sin música sigue a 0 % de CPU y con música y el notch cerrado no pasa de ~1 %.

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
