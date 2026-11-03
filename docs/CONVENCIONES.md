# Convenciones

## Commits

Formato [Conventional Commits](https://www.conventionalcommits.org/es/), en español:

```
tipo(ámbito): resumen en imperativo y minúsculas
```

| Tipo | Uso |
|---|---|
| `feat` | Capacidad nueva o visible |
| `fix` | Corrección de un error |
| `refactor` | Cambio interno sin cambiar el comportamiento |
| `docs` | Documentación |
| `art` | Assets visuales |
| `chore` | Configuración, dependencias, herramientas |
| `test` | Pruebas |

Ámbitos: `notch`, `voz`, `musica`, `llm`, `acciones`, `arte`, `app`, `docs`.

Ejemplos:
- `feat(voz): añadir push-to-talk con atajo global`
- `art(arte): añadir hoja de personaje A-001`
- `docs: cerrar decisión D-1 (Claude API)`

Reglas:
- Un commit = un cambio con sentido propio. No mezclar código con assets.
- Si toca una capacidad, el cuerpo del commit la menciona (`Capacidad: C-07`).
- Todos los commits llevan solo la autoría del dueño del repo, sin coautores.

## Ramas

- `main` siempre compila.
- Una rama por fase o capacidad: `fase-2/push-to-talk`, `arte/hoja-personaje`. Se fusiona a `main` cuando el hito funciona.

## Etiquetas

Al cerrar cada fase: `git tag v0.<fase>.0`, por ejemplo `v0.2.0` al terminar el bucle de voz.
