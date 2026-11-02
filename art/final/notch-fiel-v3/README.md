# Notch v3 — Capri en fotogramas completos

Recursos de la app para el panel abierto del notch, sacados del prototipo aprobado
`art/inbox/notch-fiel-prueba-v3/` (no se suben a GitHub; aquí está lo derivado).

| Archivo | Contenido |
|---|---|
| `frames/*.png` | Los 16 dibujos que usa la secuencia, con el mismo recorte de 644×244 px (x 280, y 2 de la maqueta de 1024×352). `15-acerca-frena` no se incluye: la secuencia lo omite. |
| `timing.json` | Secuencia exacta de `timing-final.json`: 31 exposiciones, 4000 ms. |
| `layout.json` | Geometría de la maqueta en px: notch, panel, recorte del personaje e interfaz. |

Copias con prefijo `notch-v3-` en `Sources/Capri/Resources/` (las que carga la app).

## Cómo se generan
```bash
python3 -I tools/preparar_notch_v3.py
```
El recorte es el mismo rectángulo para todos los fotogramas, sin centrar ni ajustar ninguno. Dentro de él solo se pinta con el negro del panel (`#020106`) lo que es maqueta: los rectángulos de la interfaz (se reconstruye nativa; el script comprueba que no cambian entre fotogramas) y el escritorio que asoma fuera del panel. Los negros del personaje no se tocan.

## Cómo los usa la app
- Escala: el ancho del notch de la maqueta (332 px) se iguala al del notch real. En un MacBook de 14" (185×32 pt) son 0,557 pt/px, coherente también con la altura (57 px → 32 pt).
- El panel y el recorte se colocan respecto al centro del notch real, como en la maqueta (el panel no está centrado en la cámara: va ~14 pt a la derecha).
- Los fotogramas se decodifican al arrancar y se cambian exactamente al inicio de cada exposición (`ExposureSchedule`), no a los FPS de la pantalla.
- Comprobaciones: `.build/debug/Capri --timing-check` imprime el calendario del reproductor; `--snapshot ruta.png idle t=ms` captura el panel a esos ms del loop.
