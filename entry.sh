#!/usr/bin/env bash
set -Eeuo pipefail

info () { printf "%b%s%b" "\E[1;34m❯ \E[1;36m" "${1:-}" "\E[0m\n"; }
error () { printf "%b%s%b" "\E[1;31m❯ " "ERROR: ${1:-}" "\E[0m\n" >&2; }
warn () { printf "%b%s%b" "\E[1;31m❯ " "Warning: ${1:-}" "\E[0m\n" >&2; }

trap 'error "Status $? while: $BASH_COMMAND (line $LINENO/$BASH_LINENO)"' ERR

[ ! -f "/run/entry.sh" ] && error "Script must run inside Docker container!" && exit 11
[ "$(id -u)" -ne "0" ] && error "Script must be executed with root privileges." && exit 12

echo "❯ Starting umbrelOS for Docker v$(</run/version)..."
echo "❯ For support visit https://github.com/dockur/umbrel/issues"

if [ ! -S /var/run/docker.sock ]; then
  error "Docker socket is missing? Please bind /var/run/docker.sock in your compose file." && exit 13
fi

if ! docker network inspect umbrel_main_network &>/dev/null; then
  if ! docker network create --driver=bridge --subnet="10.21.0.0/16" umbrel_main_network >/dev/null; then
    error "Failed to create network 'umbrel_main_network'!" && exit 14
  fi
  if ! docker network inspect umbrel_main_network &>/dev/null; then
    error "Network 'umbrel_main_network' does not exist?" && exit 15
  fi
fi

target=$(hostname)

if ! docker inspect "$target" &>/dev/null; then
  error "Failed to find a container with name '$target'!" && exit 16
fi

resp=$(docker inspect "$target")
network=$(echo "$resp" | jq -r '.[0].NetworkSettings.Networks["umbrel_main_network"]')

if [ -z "$network" ] || [[ "$network" == "null" ]]; then
  if ! docker network connect umbrel_main_network "$target"; then
    error "Failed to connect container to network!" && exit 17
  fi
fi

mount=$(echo "$resp" | jq -r '.[0].Mounts[] | select(.Destination == "/data").Source')

if [ -z "$mount" ] || [[ "$mount" == "null" ]] || [ ! -d "/data" ]; then
  error "You did not bind the /data folder!" && exit 18
fi

# Create directories
mkdir -p "/images"

# Convert Windows paths to Linux path
if [[ "$mount" == *":\\"* ]]; then
  mount="${mount,,}"
  mount="${mount//\\//}"
  mount="//${mount/:/}"
fi

if [[ "$mount" != "/"* ]]; then
  error "Please bind the /data folder to an absolute path!" && exit 19
fi

# Mirror external folder to local filesystem
if [[ "$mount" != "/data" ]]; then
  mkdir -p "$mount"
  rm -rf "$mount"
  ln -s /data "$mount"
fi

trap "pkill -SIGINT -f umbreld; while pgrep umbreld >/dev/null; do sleep 1; done" SIGINT SIGTERM

umbreld --data-directory "$mount" & wait $!
