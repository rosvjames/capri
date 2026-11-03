"""Generador local del demo. JSONL por stdin/stdout; el audio se entrega como WAV temporal."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import wave

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"

WIRE = sys.stdout


def send(event, **fields):
    WIRE.write(json.dumps({"event": event, **fields}, ensure_ascii=False) + "\n")
    WIRE.flush()


def clean_audio(audio, rate):
    """Reduce el fondo sin cambiar la referencia, el tono ni la velocidad de la voz."""
    import numpy as np

    resources = Path(__file__).resolve().parent
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        ffmpeg = next((p for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg") if os.access(p, os.X_OK)), None)
    if ffmpeg is None or not (resources / "capri-denoise.rnnn").is_file():
        raise RuntimeError("Falta FFmpeg o el modelo local de reducción de ruido.")

    # RNNoise trabaja a 48 kHz y retrasa 10 ms la señal. El margen permite arrancar
    # el filtro antes de la primera sílaba y recuperar la última completa.
    leading, trailing = round(rate * 0.12), round(rate * 0.20)
    padded = np.pad(audio, (leading, trailing)).astype("<f4")
    filtered = subprocess.run([
        ffmpeg, "-v", "error", "-nostdin", "-f", "f32le", "-ar", str(rate),
        "-ac", "1", "-i", "pipe:0", "-af",
        f"aresample=48000,highpass=f=65,arnndn=m=capri-denoise.rnnn:mix=1,aresample={rate}",
        "-f", "f32le", "pipe:1",
    ], input=padded.tobytes(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        cwd=resources, check=True, timeout=20)
    samples = np.frombuffer(filtered.stdout, dtype="<f4")
    start = leading + round(rate * 0.01)
    cleaned = samples[start:start + len(audio)].copy()
    if len(cleaned) != len(audio) or not np.isfinite(cleaned).all():
        raise ValueError("La limpieza no devolvió el audio completo.")

    # Los bordes llegan a cero gradualmente: no cortar una muestra de golpe.
    attack = min(round(rate * 0.005), len(cleaned))
    release = min(round(rate * 0.02), len(cleaned))
    cleaned[:attack] *= np.sin(np.linspace(0, np.pi / 2, attack)) ** 2
    cleaned[-release:] *= np.cos(np.linspace(0, np.pi / 2, release)) ** 2
    # Cola de silencio real antes de dar por terminada la reproducción.
    return np.pad(cleaned, (0, round(rate * 0.12)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", required=True)
    args = parser.parse_args()
    # La transcripción vive junto a la referencia (mismo nombre, .txt), no en el código.
    reference_text = Path(args.reference).with_suffix(".txt").read_text(encoding="utf-8").strip()
    # Las librerías imprimen mensajes de carga; stdout se reserva para el protocolo.
    with contextlib.redirect_stdout(sys.stderr):
        import mlx.core as mx
        import numpy as np
        from mlx_audio.tts.utils import load_model

        model = load_model("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    send("ready")
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            text = request["text"].strip()
            if not text:
                raise ValueError("El texto está vacío.")
            with contextlib.redirect_stdout(sys.stderr):
                mx.random.seed(7)
                chunks = list(model.generate(
                    text=text,
                    ref_audio=args.reference,
                    ref_text=reference_text,
                    lang_code="spanish", temperature=0.9, max_tokens=2000, verbose=False,
                ))
                audio = np.asarray(mx.concatenate([chunk.audio for chunk in chunks]), dtype=np.float32).reshape(-1)
                rate = chunks[0].sample_rate
                if not len(audio) or not np.isfinite(audio).all():
                    raise ValueError("Qwen no devolvió audio válido.")
                # Solo ganancia constante: aproxima el volumen de las muestras elegidas,
                # manteniendo sus silencios, timbre y dinámica. Nunca altera tono o velocidad.
                size = int(rate * 0.02)
                windows = audio[:len(audio) // size * size].reshape(-1, size)
                rms = np.sqrt(np.mean(windows * windows, axis=1))
                active = rms[rms > 0.003]
                if len(active):
                    gain = 10 ** (-17 / 20) / float(np.median(active))
                    gain = min(gain, 10 ** (-1.5 / 20) / max(float(np.abs(audio).max()), 1e-6))
                    audio = audio * gain
                audio = clean_audio(audio, rate)
                output = request["output"]
                with wave.open(output, "wb") as wav:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)
                    wav.setframerate(rate)
                    wav.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())
                del audio, chunks
                mx.clear_cache()
            send("audio", id=request["id"], output=output)
        except Exception as error:
            send("error", id=request.get("id"), error=str(error))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        send("fatal", error=str(error))
        sys.exit(1)
