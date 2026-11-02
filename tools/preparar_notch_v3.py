#!/usr/bin/env python3
"""Prepara los fotogramas de Capri del prototipo de notch v3 para la app.

Uso (desde la raíz del repo, necesita ffmpeg):
    python3 -I tools/preparar_notch_v3.py

Lee art/inbox/notch-fiel-prueba-v3/ (fotogramas de 1024x352 con la interfaz de maqueta)
y escribe en art/final/notch-fiel-v3/ y en Sources/Capri/Resources/:
  - un PNG por dibujo usado en timing-final.json, todos con el mismo recorte del personaje
  - la secuencia (timing) y la geometría de la maqueta (layout)
Los originales no se modifican.

El recorte es un rectángulo fijo, idéntico para todos los fotogramas. Dentro de él, solo
se pintan con el negro del panel dos zonas que son de la maqueta y no del personaje:
los rectángulos de la interfaz de la izquierda (se reconstruye como UI nativa; el script
comprueba que no cambian entre fotogramas) y el escritorio que asoma fuera del panel
(se detecta por relleno desde el borde del recorte en 00-reference y queda fuera del
recorte nativo del panel).
"""
import json
import shutil
import subprocess
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art/inbox/notch-fiel-prueba-v3"
DST = ROOT / "art/final/notch-fiel-v3"
RES = ROOT / "Sources/Capri/Resources"

CANVAS = (1024, 352)
# Geometría medida sobre frames/00-reference.png (px de la maqueta; y=0 es el borde superior de la pantalla).
NOTCH = dict(x=322, y=0, w=332, h=57)
PANEL = dict(x=116, y=0, w=796, h=242, topFlareRadius=12, bottomRadius=62)
CROP = dict(x=280, y=2, w=644, h=244)      # la fila 0-1 es el borde de la captura de la maqueta
# Interfaz de maqueta que se pinta de negro (se reconstruye nativa): rectángulos de cada elemento + 3 px.
UI_RECTS = [(143, 58, 240, 81), (145, 94, 275, 123), (143, 139, 302, 197)]
PANEL_BLACK = (2, 1, 6)
UI = {
    "title": dict(x=148, y=62, capHeight=15, text="CAPRI", color="A1A2A9"),
    "dot": dict(x=221, y=61, size=15, color="14FF73"),
    "message": dict(x=148, y=98, capHeight=17, text="Aquí estoy.", color="FFFFFF"),
    "button": dict(x=146, y=142, w=153, h=52, stroke=3, text="Hablar", color="14FF73"),
}


def read_rgba(path):
    w, h = CANVAS
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
                         check=True, capture_output=True).stdout
    assert len(raw) == w * h * 4, f"{path.name}: tamaño inesperado"
    return raw


def crop(raw):
    w = CANVAS[0]
    out = bytearray()
    for y in range(CROP["y"], CROP["y"] + CROP["h"]):
        i = (y * w + CROP["x"]) * 4
        out += raw[i:i + CROP["w"] * 4]
    return out


def is_desktop(p):
    """Píxel del escritorio o de su borde suavizado: gris azulado, nunca negro ni color del personaje."""
    r, g, b = p[0], p[1], p[2]
    return b - r > 8 and max(r, g, b) >= 24 and r < 90 and g < 110 and b < 140


def mockup_mask(reference):
    """Píxeles del recorte que pertenecen a la maqueta: zona de interfaz + escritorio fuera del panel.

    El escritorio se encuentra por relleno desde los bordes del recorte, así que un píxel azulado
    rodeado de personaje (por ejemplo, el borde de un iris) nunca se toca.
    """
    cw, ch = CROP["w"], CROP["h"]
    px = lambda x, y: reference[(y * cw + x) * 4:(y * cw + x) * 4 + 3]
    mask = bytearray(cw * ch)
    queue = deque()
    for x in range(cw):
        for y in (0, ch - 1):
            queue.append((x, y))
    for y in range(ch):
        for x in (0, cw - 1):
            queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        k = y * cw + x
        if mask[k] or not is_desktop(px(x, y)):
            continue
        mask[k] = 1
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < cw and 0 <= ny < ch:
                queue.append((nx, ny))
    ui = bytearray(cw * ch)
    for x0, y0, x1, y1 in UI_RECTS:
        for y in range(max(y0, CROP["y"]), y1 + 1):
            for x in range(max(x0, CROP["x"]), x1 + 1):
                ui[(y - CROP["y"]) * cw + (x - CROP["x"])] = 1
    return mask, ui


def paint(img, mask):
    out = bytearray(img)
    for k, m in enumerate(mask):
        if m:
            out[k * 4:k * 4 + 4] = bytes(PANEL_BLACK + (255,))
    return out


def main():
    timing = json.loads((SRC / "timing-final.json").read_text())
    sequence = timing["sequence"]
    used = list(dict.fromkeys(e["frame"] for e in sequence))
    assert sum(e["durationMs"] for e in sequence) == timing["sequenceDurationMs"]

    crops = {name: crop(read_rgba(SRC / "frames" / f"{name}.png")) for name in used}
    desktop, ui = mockup_mask(crops["00-reference"])

    # La interfaz de maqueta debe ser idéntica en todos los fotogramas: si no, el rectángulo tocaría al personaje.
    ref = crops["00-reference"]
    for name, img in crops.items():
        diff = sum(1 for k, m in enumerate(ui) if m and img[k * 4:k * 4 + 3] != ref[k * 4:k * 4 + 3])
        if diff:
            sys.exit(f"{name}: {diff} píxeles de la zona de interfaz cambian entre fotogramas; revisar UI_RECTS")
    mask = bytes(a | b for a, b in zip(desktop, ui))

    (DST / "frames").mkdir(parents=True, exist_ok=True)
    for name, img in crops.items():
        out = DST / "frames" / f"{name}.png"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba",
                        "-s", f"{CROP['w']}x{CROP['h']}", "-i", "-", "-pix_fmt", "rgba", str(out)],
                       input=bytes(paint(img, mask)), check=True)
        shutil.copyfile(out, RES / f"notch-v3-{name}.png")

    timing_out = {
        "source": "art/inbox/notch-fiel-prueba-v3/timing-final.json",
        "sequenceDurationMs": timing["sequenceDurationMs"],
        "sequence": sequence,
        "omittedDrawings": timing.get("omittedDrawings", []),
    }
    layout_out = {
        "source": "art/inbox/notch-fiel-prueba-v3/frames/00-reference.png",
        "units": "píxeles de la maqueta de 1024x352; y=0 es el borde superior de la pantalla",
        "canvas": list(CANVAS),
        "notch": NOTCH,
        "panel": PANEL,
        "characterCrop": CROP,
        "panelBlack": "%02X%02X%02X" % PANEL_BLACK,
        "ui": UI,
    }
    for name, data in (("timing", timing_out), ("layout", layout_out)):
        text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        (DST / f"{name}.json").write_text(text)
        (RES / f"notch-v3-{name}.json").write_text(text)
    print(f"{len(crops)} fotogramas, {sum(mask)} píxeles de maqueta pintados por fotograma, {len(sequence)} exposiciones")


if __name__ == "__main__":
    main()
