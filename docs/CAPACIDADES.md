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
| C-04 | Revisión de código | "¿Qué errores ves en este código?" | LLM + contexto: portapapeles, texto seleccionado o archivo arrastrado al notch |
| C-05 | Explicar errores | "¿Por qué me da este error?" | Igual que C-04, con el mensaje de error como contexto |
| C-06 | Hora y fecha | "¿Qué hora es?" | Local, sin LLM |
| C-07 | Abrir aplicaciones | "Abre Safari", "abre Claude", "abre ChatGPT" | Local (`NSWorkspace`); el LLM solo identifica la intención |
| C-08 | Abrir sitios | "Abre YouTube" | Local; abre la URL en el navegador por defecto |
| C-09 | Música (Spotify) | "Pon tal canción", "pausa", "¿qué suena?" | AppleScript sobre Spotify |
| C-10 | Interrumpir y silenciar | Esc la calla o cancela; modo silencio; se oculta en pantalla completa | Local |

### Principio de diseño
Lo que se puede resolver localmente (hora, abrir apps, música) **no pasa por el LLM para ejecutarse**: el LLM solo decide *qué* herramienta usar (tool calling). Así es rápido, barato y predecible.

## Después (v2+, no comprometido)

- C-20 Palabra de activación ("Capri") en vez de atajo de teclado
- C-21 Memoria de conversaciones y preferencias
- C-22 Leer la ventana activa (captura de pantalla) como contexto de código
- C-23 Recordatorios y temporizadores
- C-24 Comentarios espontáneos / personalidad proactiva
- C-25 Presencia en el escritorio: aparecer fuera del notch, moverse e interactuar con la pantalla (D-7)
- C-26 Narrar en el notch lo que hace Claude Code (hooks): acción actual, avisos de permiso, resumen al terminar
- C-27 Reaccionar al Mac: cargador, batería, AirPods, CPU al máximo
- C-28 Reacciones en espera sin gastar IA (miradas, gestos)

Origen de C-10 y C-25 a C-28: análisis de otros proyectos en `docs/REFERENCIAS.md`.

## Decisiones

### Cerradas (2026-11-01)

| # | Pregunta | Decisión |
|---|---|---|
| D-1 | ¿Qué LLM? | Claude API como principal, detrás de un protocolo para poder añadir Ollama (local) después |
| D-2 | ¿Cómo se activa? | Atajo de teclado global (push-to-talk) en v1; palabra de activación en v2 (C-20). La tecla exacta se elige en la Fase 2 |
| D-3 | ¿Qué app de música? | Spotify |
| D-4 | ¿Reconocimiento de voz? | Speech de Apple (nativo, gratis) en v1 |
| D-5 | ¿Voz de respuesta? | Voz del sistema en v1; voz con más carácter después (ElevenLabs Voice Design o TTS local tipo Kokoro) |
| D-6 | ¿Repositorio público? | Público, con aviso de fan project no comercial |

### Abiertas

| # | Pregunta | Notas |
|---|---|---|
| D-7 | ¿Cuándo y cómo aparece Capri en el escritorio, fuera del notch? | Ver C-25. Se decide cuando el notch y la voz funcionen |
