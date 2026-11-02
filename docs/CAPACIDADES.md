# Capacidades de Capri

Asistente de escritorio para macOS con la estética de Capri (*Cyberpunk: Edgerunners 2*). Vive en el notch y se usa principalmente por voz.

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
| C-09 | Música | "Pon tal canción" | Control de la app de música vía AppleScript / URL scheme |

### Principio de diseño
Lo que se puede resolver localmente (hora, abrir apps, música) **no pasa por el LLM para ejecutarse**: el LLM solo decide *qué* herramienta usar (tool calling). Así es rápido, barato y predecible.

## Después (v2+, no comprometido)

- C-20 Palabra de activación ("Capri") en vez de atajo de teclado
- C-21 Memoria de conversaciones y preferencias
- C-22 Leer la ventana activa (captura de pantalla) como contexto de código
- C-23 Recordatorios y temporizadores
- C-24 Comentarios espontáneos / personalidad proactiva

## Decisiones abiertas

| # | Pregunta | Opciones | Recomendación |
|---|---|---|---|
| D-1 | ¿Qué LLM? | Claude API (de pago, mejor en código) · Ollama local (gratis, más limitado) · ambos | Claude API como principal, con capa abstracta para añadir Ollama |
| D-2 | ¿Cómo se activa? | Atajo de teclado (push-to-talk) · palabra de activación | Atajo en v1; palabra de activación en v2 (C-20) |
| D-3 | ¿Qué app de música? | Spotify · Apple Music | — (depende de cuál uses) |
| D-4 | ¿Reconocimiento de voz? | Speech de Apple (nativo, gratis) · Whisper local | Speech de Apple en v1 |
| D-5 | ¿Voz de respuesta? | Voces del sistema · TTS local · TTS en la nube | Voz del sistema en v1; evaluar una voz con más carácter después |
| D-6 | ¿Repositorio público? | Público · privado | Público si va al CV; arte generado con aviso de fan project no comercial |
