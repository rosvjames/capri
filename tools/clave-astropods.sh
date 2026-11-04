#!/bin/bash
# Guarda en el Llavero la clave del AI Gateway de Astropods para que Capri hable con Claude con esos créditos.
#
# Astropods no muestra la clave en su web: se la inyecta al contenedor de un proyecto local, y la de
# desarrollo caduca a las 24 h. Este script levanta un proyecto mínimo, la lee del contenedor, la guarda
# (sin mostrarla) y apaga el proyecto. Cuando caduque, se vuelve a correr.
#
# Uso:  tools/clave-astropods.sh
# Requisitos: `ast` instalado y con sesión iniciada (`ast login`), y Docker abierto.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="$PWD/build/Capri.app"
# El proyecto vive fuera del repositorio.
DIR="$HOME/.capri"
PROYECTO=capri-gateway
# El instalador de Astropods pone `ast` aquí y solo lo añade al PATH de las terminales interactivas.
export PATH="$HOME/.ast/bin:$PATH"

command -v ast >/dev/null || { echo "Falta ast: https://docs.astropods.com/install-cli"; exit 1; }
docker info >/dev/null 2>&1 || { echo "Abre Docker y vuelve a intentarlo."; exit 1; }

mkdir -p "$DIR"
if [[ ! -d "$DIR/$PROYECTO" ]]; then
  (cd "$DIR" && ast project create "$PROYECTO" --model gateway -y)
fi
cd "$DIR/$PROYECTO"
ast project start --background

# El contenedor del agente es el que recibe las variables del gateway; puede tardar en arrancar.
contenedor=""
for _ in $(seq 30); do
  for nombre in $(docker ps --format '{{.Names}}'); do
    if docker exec "$nombre" printenv ASTRO_GATEWAY_API_KEY >/dev/null 2>&1; then
      contenedor="$nombre"
      break 2
    fi
  done
  sleep 2
done
if [[ -z "$contenedor" ]]; then
  ast project stop
  echo "No encontré el contenedor con la clave del gateway (docker ps)."
  exit 1
fi

url="$(docker exec "$contenedor" printenv ASTRO_GATEWAY_URL)"
# -U reemplaza la clave anterior; -T deja que la app empaquetada la lea sin preguntar cada vez.
confianza=(-T /usr/bin/security)
[[ -d "$APP" ]] && confianza+=(-T "$APP")
security add-generic-password -U -s com.rosvjames.capri -a astropods "${confianza[@]}" \
  -w "$(docker exec "$contenedor" printenv ASTRO_GATEWAY_API_KEY)"
defaults write com.rosvjames.capri astropods-url "$url"
ast project stop

echo "Clave de Astropods guardada en el Llavero (caduca en 24 h). Gateway: $url"
echo "Reinicia Capri para que la use."
