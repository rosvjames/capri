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

## Fase 1 — Identidad visual 
Va en paralelo con la Fase 2.
- ⬜ Hoja de personaje de Capri (referencia maestra)
- ⬜ Paleta y tipografía definitivas a partir de la hoja
- ⬜ Sprites por estado (espera, escuchando, pensando, respondiendo)
- ⬜ Integrar los assets en el notch y reemplazar el placeholder

## Fase 2 — Bucle de voz (C-01)
- ⬜ Atajo de teclado global para hablar (push-to-talk)
- ⬜ Reconocimiento de voz en español (permisos de micrófono y voz)
- ⬜ Respuesta hablada (TTS)
- ⬜ Estados del notch conectados al flujo real
- ⬜ Esc para callarla, modo silencio, ocultarse en pantalla completa (C-10)
- Hito: le hablas y repite lo que entendió, en voz

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
Capacidades C-20 en adelante, según interés.
