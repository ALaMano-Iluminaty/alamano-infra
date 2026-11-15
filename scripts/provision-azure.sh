#!/bin/bash
# Aprovisiona la topologia de 4 VMs en Azure (ver docs/topologia-4-vms.md).
# Requiere: az cli con sesion iniciada (az login).
# Uso:
#   LOCATION=eastus MI_IP=$(curl -s ifconfig.me) bash scripts/provision-azure.sh
#
# Deja las IPs publica/privada en resultados/vms-<stamp>.txt.
set -euo pipefail

RG="${RG:-alamano-rg}"
LOCATION="${LOCATION:-eastus}"
VNET="${VNET:-alamano-vnet}"
MI_IP="${MI_IP:-0.0.0.0/0}"
IMAGE="${IMAGE:-Ubuntu2204}"
SIZE="${SIZE:-Standard_B2s}"
ADMIN_USER="${ADMIN_USER:-alamano}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../resultados"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$OUT_DIR/vms-$STAMP.txt"

echo ">> creando grupo $RG en $LOCATION"
az group create -n "$RG" -l "$LOCATION" -o none

echo ">> VNet + subred interna"
az network vnet create -g "$RG" -n "$VNET" --address-prefix 10.0.0.0/16 \
  --subnet-name interna --subnet-prefix 10.0.1.0/24 -o none

echo ">> NSG de la VM de entrada: 22 (solo mi IP), 80, 443"
az network nsg create -g "$RG" -n nsg-entrada -o none
az network nsg rule create -g "$RG" --nsg-name nsg-entrada -n ssh \
  --priority 100 --protocol Tcp --destination-port-ranges 22 --source-address-prefixes "$MI_IP" -o none
az network nsg rule create -g "$RG" --nsg-name nsg-entrada -n http \
  --priority 110 --protocol Tcp --destination-port-ranges 80 443 -o none

echo ">> NSG interno: entre VMs y ssh solo desde mi IP"
az network nsg create -g "$RG" -n nsg-interno -o none
az network nsg rule create -g "$RG" --nsg-name nsg-interno -n ssh \
  --priority 100 --protocol Tcp --destination-port-ranges 22 --source-address-prefixes "$MI_IP" -o none
az network nsg rule create -g "$RG" --nsg-name nsg-interno -n intra \
  --priority 200 --protocol '*' --destination-port-ranges '*' --source-address-prefixes 10.0.0.0/16 -o none

crear_vm() {
  local nombre="$1" nsg="$2" con_ip_publica="$3"
  local flags=(--resource-group "$RG" --name "$nombre" --image "$IMAGE" --size "$SIZE"
    --admin-username "$ADMIN_USER" --generate-ssh-keys
    --vnet-name "$VNET" --subnet interna --nsg "$nsg")
  if [[ "$con_ip_publica" == "no" ]]; then
    flags+=(--public-ip-address "")
  fi
  echo ">> VM $nombre"
  az vm create "${flags[@]}" -o none
}

crear_vm vm-entrada nsg-entrada si
crear_vm vm-app-1 nsg-interno no
crear_vm vm-app-2 nsg-interno no
crear_vm vm-datos nsg-interno no

{
  echo "Grupo: $RG   VNet: $VNET"
  for n in vm-entrada vm-app-1 vm-app-2 vm-datos; do
    PUB=$(az vm list-ip-addresses -g "$RG" -n "$n" \
      --query '[].virtualMachine.network.publicIpAddresses[0].ipAddress' -o tsv 2>/dev/null || echo "-")
    PRI=$(az vm list-ip-addresses -g "$RG" -n "$n" \
      --query '[].virtualMachine.network.privateIpAddresses[0]' -o tsv)
    echo "  $n   publica=${PUB:--}   privada=$PRI"
  done
} | tee "$OUT"

echo
echo "Siguiente paso: bootstrap-vm.sh en cada VM, luego deploy.sh en la de entrada"
echo "IPs guardadas en $OUT"
