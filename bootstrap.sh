#!/usr/bin/env bash
set -Eeuo pipefail

# This bootstrap is safe to rerun: it only installs missing prerequisites,
# clones the repository if needed, and then hands off the actual provisioning to
# the idempotent Ansible playbook.

REPO_DIR="${HOME}/my-workstation"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo -v

while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" || exit
done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "${SUDO_KEEPALIVE_PID}"' EXIT

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ansible

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  if [[ -d "${SCRIPT_DIR}/.git" ]]; then
    git clone "${SCRIPT_DIR}" "${REPO_DIR}"
  elif [[ -n "${DOTFILES_REPO_URL:-}" ]]; then
    git clone "${DOTFILES_REPO_URL}" "${REPO_DIR}"
  else
    echo "No se pudo determinar el origen del repositorio. Exporta DOTFILES_REPO_URL e inténtalo de nuevo." >&2
    exit 1
  fi
else
  echo "El repositorio ya existe en ${REPO_DIR}, omitiendo clonación."
  git -C "${REPO_DIR}" pull --ff-only
fi

cd "${REPO_DIR}"
ansible-playbook ansible/local.yml "$@"