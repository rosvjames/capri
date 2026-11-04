"""Voz local con Qwen. JSONL por stdin/stdout; el audio se entrega por trozos mientras se genera.

Petición: {"id", "text"}. Respuestas: {"event": "chunk", "id", "rate", "pcm"} (PCM de 16 bits en base64),
varias por frase, y al final {"event": "done", "id"}; o {"event": "error", "id", "error"}.
"""
import argparse
import base64
import contextlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"

WIRE = sys.stdout
# Cada cuánto entrega Qwen audio nuevo (s): el primer trozo llega en ~0,8 s en vez de esperar la frase entera.
STREAMING_INTERVAL = 0.6
# Solo ganancia constante: acerca el volumen al de las muestras elegidas sin tocar silencios, timbre,
# dinámica, tono ni velocidad. Es fija porque el audio llega por trozos y el primero suele ser más suave
# que el resto: calcularla con él saturaba. Antes, con la frase entera, salía entre +12 y +15 dB
# (casi siempre limitada por los picos) en las siete frases medidas.
GAIN = 10 ** (13 / 20)


def send(event, **fields):
    WIRE.write(json.dumps({"event": event, **fields}, ensure_ascii=False) + "\n")
    WIRE.flush()


def find_ffmpeg():
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        ffmpeg = next((p for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg") if os.access(p, os.X_OK)), None)
    return ffmpeg


class StreamCleaner:
    """Reduce el fondo sin cambiar el tono ni la velocidad de la voz, a medida que llega el audio.

    Un solo proceso de FFmpeg por frase: RNNoise guarda estado entre bloques, así que filtrar cada trozo
    por separado dejaría costuras. RNNoise trabaja a 48 kHz y retrasa 10 ms la señal; el margen inicial
    permite arrancar el filtro antes de la primera sílaba y el final, recuperar la última completa.
    """

    def __init__(self, rate):
        import numpy as np

        self.np = np
        self.rate = rate
        resources = Path(__file__).resolve().parent
        ffmpeg = find_ffmpeg()
        if ffmpeg is None or not (resources / "capri-denoise.rnnn").is_file():
            raise RuntimeError("Falta FFmpeg o el modelo local de reducción de ruido.")
        self.process = subprocess.Popen([
            ffmpeg, "-v", "error", "-nostdin", "-f", "f32le", "-ar", str(rate),
            "-ac", "1", "-i", "pipe:0", "-af",
            f"aresample=48000,highpass=f=65,arnndn=m=capri-denoise.rnnn:mix=1,aresample={rate}",
            "-flush_packets", "1", "-f", "f32le", "pipe:1",
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=resources)
        self.output = bytearray()
        self.lock = threading.Lock()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        self.skip = round(rate * 0.12) + round(rate * 0.01)
        self.fed = 0
        self.taken = 0
        self.attack = min(round(rate * 0.005), rate)
        self.release = round(rate * 0.02)
        self.tail = np.zeros(0, dtype=np.float32)
        self._write(np.zeros(round(rate * 0.12), dtype=np.float32))

    def _read(self):
        while True:
            data = self.process.stdout.read1(16384)
            if not data:
                return
            with self.lock:
                self.output += data

    def _write(self, audio):
        self.process.stdin.write(audio.astype("<f4").tobytes())
        self.process.stdin.flush()

    def feed(self, audio):
        self._write(audio)
        self.fed += len(audio)

    def take(self, final=False):
        """Audio limpio disponible. Se guarda el final de lo recibido para suavizar el corte al terminar."""
        np = self.np
        with self.lock:
            usable = len(self.output) // 4 * 4
            data = bytes(self.output[:usable])
            del self.output[:usable]
        samples = np.frombuffer(data, dtype="<f4")
        if self.skip:
            drop = min(self.skip, len(samples))
            samples, self.skip = samples[drop:], self.skip - drop
        samples = samples[:max(0, self.fed - self.taken - len(self.tail))]
        samples = np.concatenate([self.tail, samples]).astype(np.float32)
        if not np.isfinite(samples).all():
            raise ValueError("La limpieza devolvió audio no válido.")
        keep = 0 if final else min(self.release, len(samples))
        ready, self.tail = samples[:len(samples) - keep].copy(), samples[len(samples) - keep:]
        if self.taken == 0 and len(ready):
            n = min(self.attack, len(ready))
            ready[:n] *= np.sin(np.linspace(0, np.pi / 2, n)) ** 2
        self.taken += len(ready)
        if final:
            n = min(self.release, len(ready))
            if n:
                ready[-n:] *= np.cos(np.linspace(0, np.pi / 2, n)) ** 2
            # Cola de silencio real antes de dar por terminada la reproducción.
            ready = np.concatenate([ready, np.zeros(round(self.rate * 0.12), dtype=np.float32)])
        return ready

    def finish(self):
        self._write(self.np.zeros(round(self.rate * 0.20), dtype=self.np.float32))
        self.process.stdin.close()
        self.reader.join(timeout=20)
        self.process.wait(timeout=20)
        return self.take(final=True)

    def close(self):
        if self.process.poll() is None:
            self.process.kill()


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
        # La primera generación compila los kernels y tarda el doble: se hace aquí, mientras James habla,
        # y no con la primera frase de la respuesta.
        for _ in model.generate(text="Hola.", ref_audio=args.reference, ref_text=reference_text,
                                lang_code="spanish", max_tokens=40, verbose=False,
                                stream=True, streaming_interval=STREAMING_INTERVAL):
            break
        mx.clear_cache()
    send("ready")

    def emit(request_id, audio, rate):
        if len(audio):
            pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes()
            send("chunk", id=request_id, rate=rate, pcm=base64.b64encode(pcm).decode("ascii"))

    for line in sys.stdin:
        request = {}
        cleaner = None
        try:
            request = json.loads(line)
            text = request["text"].strip()
            if not text:
                raise ValueError("El texto está vacío.")
            rate = None
            with contextlib.redirect_stdout(sys.stderr):
                mx.random.seed(7)
                for chunk in model.generate(
                    text=text,
                    ref_audio=args.reference,
                    ref_text=reference_text,
                    lang_code="spanish", temperature=0.9, max_tokens=2000, verbose=False,
                    stream=True, streaming_interval=STREAMING_INTERVAL,
                ):
                    audio = np.asarray(chunk.audio, dtype=np.float32).reshape(-1)
                    if not len(audio) or not np.isfinite(audio).all():
                        raise ValueError("Qwen no devolvió audio válido.")
                    if cleaner is None:
                        rate = chunk.sample_rate
                        cleaner = StreamCleaner(rate)
                    cleaner.feed(audio * GAIN)
                    emit(request["id"], cleaner.take(), rate)
                if cleaner is None:
                    raise ValueError("Qwen no devolvió audio.")
                emit(request["id"], cleaner.finish(), rate)
                mx.clear_cache()
            send("done", id=request["id"])
        except Exception as error:
            send("error", id=request.get("id"), error=str(error))
        finally:
            if cleaner is not None:
                cleaner.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        send("fatal", error=str(error))
        sys.exit(1)
