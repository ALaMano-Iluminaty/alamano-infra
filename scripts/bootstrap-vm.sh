#!/bin/bash
# Se corre UNA vez en la VM Ubuntu recien creada:  bash bootstrap-vm.sh
set -euo pipefail

curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"

# 2 GB de swap: compilar varias imagenes Maven en una VM de 4 GB se queda sin RAM.
if ! swapon --show | grep -q swapfile; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

sudo apt-get update -y && sudo apt-get install -y git openssl
echo "Listo. Cierra la sesion SSH y vuelve a entrar para que aplique el grupo docker."
