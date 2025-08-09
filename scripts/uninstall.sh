#!/usr/bin/env bash
set -Eeuo pipefail
SERVICE=${SERVICE:-vpnpanel-backend}
INSTALL_DIR=${INSTALL_DIR:-/opt/vpnpanel}
SITE=${SITE:-vpnpanel.conf}

echo "[*] Stopping service..."
sudo systemctl stop "$SERVICE" || true
sudo systemctl disable "$SERVICE" || true
sudo rm -f "/etc/systemd/system/${SERVICE}.service"
sudo systemctl daemon-reload

echo "[*] Removing nginx site..."
sudo rm -f "/etc/nginx/sites-enabled/${SITE}" "/etc/nginx/sites-available/${SITE}" || true
sudo systemctl restart nginx || true

echo "[*] Removing app files..."
sudo rm -rf "${INSTALL_DIR}"
echo "Uninstalled."
