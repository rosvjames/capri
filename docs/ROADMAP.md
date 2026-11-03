# Roadmap

Fases en orden. Cada fase termina con algo que se puede probar y con su estado actualizado aquí.
Estados: ⬜ pendiente · 🟨 en curso · ✅ hecha

## Fase 0 — Base del proyecto 🟨
- ✅ Paquete Swift que compila sin Xcode (`swift build`)
- ✅ Prototipo visual del notch con estados simulados (C-02, provisional)
- ✅ Documentación: capacidades, roadmap, estética, convenciones
- ✅ Repositorio en GitHub y primer push ([rosvjames/capri](https://github.com/rosvjames/capri))
- ✅ Cerrar decisiones D-1 a D-6 (`docs/CAPACIDADES.md`)
- ✅ Análisis de otros proyectos de Capri (`docs/REFERENCIAS.md`)

## Fase 1 — Identidad visual 🟨
Rama: `fase-1/identidad-visual`.
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
- ⬜ Tipografía de interfaz
- ⬜ Icono de la barra de menús por código (máscara y ojos)
- ✅ Panel abierto con el prototipo aprobado v3: fotogramas completos con sus duraciones e interfaz nativa (`NotchPresence.swift`, `art/final/notch-fiel-v3/`)
- ~~Base anime sin rasgos (A-005)~~: sustituida por los fotogramas completos
- ⬜ Notch cerrado con el enfoque de fotogramas (hoy usa la cara chibi por capas)
- Hito: el notch muestra a Capri cambiando de expresión según el estado

## Fase 2 — Bucle de voz (C-01)
- ⬜ Atajo de teclado global para hablar (push-to-talk)
- ⬜ Reconocimiento de voz en español (permisos de micrófono y voz)
- ⬜ Respuesta hablada (TTS)
- ⬜ Estados del notch conectados al flujo real
- ⬜ Esc para callarla, modo silencio, ocultarse en pantalla completa (C-10)
- Hito: le hablas y repite lo que entendió, en voz

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
- ⬜ Respuestas con bloques de código copiables en el panel
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
- ⬜ README con GIF/video de demo, diagrama de arquitectura
- ⬜ Release v1.0

## Fase 6+ — Extras
Capacidades C-20 en adelante, según interés. Candidata destacada: C-30, uso de IA en el notch.
