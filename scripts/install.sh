#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/vpnpanel}"
SYSTEM_USER="${SYSTEM_USER:-vpnpanel}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
DOMAIN="${DOMAIN:-}"
ENABLE_HTTPS="${ENABLE_HTTPS:-false}"
EMAIL="${EMAIL:-}"
NGINX_SITE="vpnpanel.conf"
SERVICE_NAME="vpnpanel-backend"

log(){ echo -e "\033[1;36m[+] $*\033[0m"; }
warn(){ echo -e "\033[1;33m[!] $*\033[0m"; }
err(){ echo -e "\033[1;31m[✗] $*\033[0m" >&2; }
usage(){
cat <<EOF
VPN Panel Pro — Installer
  --repo URL            Git repo (required), e.g. https://github.com/USER/REPO.git
  --branch BR           Branch (default: main)
  --install-dir PATH    Install dir (default: /opt/vpnpanel)
  --user NAME           System user (default: vpnpanel)
  --domain DOMAIN       Public domain (optional)
  --enable-https        Let's Encrypt (needs --domain and --email)
  --email you@example.com
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_URL="$2"; shift 2;;
    --branch) REPO_BRANCH="$2"; shift 2;;
    --install-dir) INSTALL_DIR="$2"; shift 2;;
    --user) SYSTEM_USER="$2"; shift 2;;
    --domain) DOMAIN="$2"; shift 2;;
    --enable-https) ENABLE_HTTPS="true"; shift 1;;
    --email) EMAIL="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done
[[ -z "${REPO_URL}" ]] && { err "--repo is required"; exit 1; }

if ! command -v apt-get >/dev/null 2>&1; then
  err "Only Ubuntu/Debian (apt) are supported."
  exit 1
fi

log "Installing prerequisites..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl unzip ca-certificates nginx python3 python3-venv python3-pip sqlite3

log "Preparing user & directories..."
if ! id -u "${SYSTEM_USER}" >/dev/null 2>&1; then
  sudo useradd -r -m -d "${INSTALL_DIR}" -s /usr/sbin/nologin "${SYSTEM_USER}" || true
fi
sudo mkdir -p "${INSTALL_DIR}"
sudo chown -R "${SYSTEM_USER}:${SYSTEM_USER}" "${INSTALL_DIR}"

log "Fetching code: ${REPO_URL} (branch ${REPO_BRANCH})"
if [[ -d "${INSTALL_DIR}/src/.git" ]]; then
  sudo -u "${SYSTEM_USER}" git -C "${INSTALL_DIR}/src" fetch --all
  sudo -u "${SYSTEM_USER}" git -C "${INSTALL_DIR}/src" checkout "${REPO_BRANCH}"
  sudo -u "${SYSTEM_USER}" git -C "${INSTALL_DIR}/src" pull --ff-only origin "${REPO_BRANCH}"
else
  sudo -u "${SYSTEM_USER}" git clone --branch "${REPO_BRANCH}" --depth 1 "${REPO_URL}" "${INSTALL_DIR}/src"
fi

[[ -d "${INSTALL_DIR}/src/backend" ]] || { err "Missing backend/ in repo"; exit 1; }
[[ -f "${INSTALL_DIR}/src/backend/requirements.txt" ]] || { err "Missing backend/requirements.txt"; exit 1; }
[[ -d "${INSTALL_DIR}/src/frontend" ]] || { err "Missing frontend/ in repo"; exit 1; }

log "Setting up Python venv & deps..."
sudo -u "${SYSTEM_USER}" bash -c "cd '${INSTALL_DIR}/src/backend' && ${PYTHON_BIN} -m venv .venv"
# --- Robust: absolute pip + absolute requirements path ---
sudo -u "${SYSTEM_USER}" bash -c "'${INSTALL_DIR}/src/backend/.venv/bin/pip' install --upgrade pip && '${INSTALL_DIR}/src/backend/.venv/bin/pip' install -r '${INSTALL_DIR}/src/backend/requirements.txt'"

log "Ensuring .env (from example or auto-generated)..."
ENV_PATH="${INSTALL_DIR}/src/backend/.env"
EXAMPLE_PATH="${INSTALL_DIR}/src/backend/.env.example"
if [[ ! -f "${ENV_PATH}" ]]; then
  ACCESS_SECRET="$(head -c 32 /dev/urandom | base64)"
  JWT_SECRET="$(head -c 32 /dev/urandom | base64)"
  if [[ -f "${EXAMPLE_PATH}" ]]; then
    sudo -u "${SYSTEM_USER}" cp "${EXAMPLE_PATH}" "${ENV_PATH}"
    sudo -u "${SYSTEM_USER}" bash -c "sed -i \"s|APP_SECRET=.*|APP_SECRET=${ACCESS_SECRET}|g\" '${ENV_PATH}'"
    sudo -u "${SYSTEM_USER}" bash -c "sed -i \"s|JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|g\" '${ENV_PATH}'"
    if [[ -n "${DOMAIN}" ]]; then
      sudo -u "${SYSTEM_USER}" bash -c "sed -i \"s|CORS_ORIGINS=.*|CORS_ORIGINS=http://${DOMAIN},https://${DOMAIN}|g\" '${ENV_PATH}'"
    fi
  else
    sudo -u "${SYSTEM_USER}" bash -c "cat > '${ENV_PATH}'" <<EOF
APP_NAME=VPN Panel Pro
APP_DEBUG=false
APP_SECRET=${ACCESS_SECRET}
CORS_ORIGINS=${DOMAIN:+http://${DOMAIN},https://${DOMAIN}}
DATABASE_URL=sqlite:///./vpnpanel.db
JWT_SECRET=${JWT_SECRET}
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7
MARZBAN_API_URL=
MARZBAN_TOKEN=
SANAEI_API_URL=
SANAEI_TOKEN=
PAYMENT_PROVIDER=mock
CALLBACK_BASE_URL=http://localhost:${BACKEND_PORT}
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
EOF
  fi
fi

log "Patching frontend API to '/api'"
sudo sed -i 's|const API = ".*";|const API = "/api";|' "${INSTALL_DIR}/src/frontend/index.html" || true

log "Installing systemd service..."
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
sudo bash -c "cat > '${SERVICE_FILE}'" <<UNIT
[Unit]
Description=VPN Panel Pro Backend (FastAPI)
After=network.target

[Service]
Type=simple
User=${SYSTEM_USER}
WorkingDirectory=${INSTALL_DIR}/src/backend
Environment=PATH=${INSTALL_DIR}/src/backend/.venv/bin
ExecStart=${INSTALL_DIR}/src/backend/.venv/bin/uvicorn app.main:app --host ${BACKEND_HOST} --port ${BACKEND_PORT}
Restart=on-failure
RestartSec=3

# Hardening
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=full
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=${INSTALL_DIR}
LockPersonality=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"

log "Configuring nginx..."
SITE_CONF="/etc/nginx/sites-available/${NGINX_SITE}"
sudo bash -c "cat > '${SITE_CONF}'" <<'NGINX'
server {
    listen 80;
    server_name _;

    root /opt/vpnpanel/src/frontend;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;

    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy no-referrer;

    location /api/ {
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        proxy_pass http://127.0.0.1:8000/;
    }

    location / {
        try_files $uri /index.html;
    }
}
NGINX

sudo sed -i "s|/opt/vpnpanel|${INSTALL_DIR}|g" "${SITE_CONF}"
sudo sed -i "s|127.0.0.1:8000|${BACKEND_HOST}:${BACKEND_PORT}|g" "${SITE_CONF}"
if [[ -n "${DOMAIN}" ]]; then
  sudo sed -i "s|server_name _;|server_name ${DOMAIN};|g" "${SITE_CONF}"
fi

sudo ln -sf "${SITE_CONF}" "/etc/nginx/sites-enabled/${NGINX_SITE}"
sudo rm -f /etc/nginx/sites-enabled/default || true
sudo nginx -t
sudo systemctl restart nginx

if [[ "${ENABLE_HTTPS}" == "true" ]]; then
  if [[ -z "${DOMAIN}" || -z "${EMAIL}" ]]; then
    warn "ENABLE_HTTPS=true needs --domain and --email; skipping"
  else
    log "Obtaining Let's Encrypt certificate for ${DOMAIN}"
    sudo apt-get install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}" --redirect || true
  fi
fi

log "Smoke test..."
sleep 1
if curl -fsS "http://${BACKEND_HOST}:${BACKEND_PORT}/health" >/dev/null; then
  log "Backend health OK"
else
  warn "Backend health endpoint not reachable locally (check service logs)."
fi

echo "---------------------------------------------"
echo "Install completed."
if [[ -n "${DOMAIN}" ]]; then
  echo "Frontend:  http://${DOMAIN} (https if enabled)"
  echo "API:       http://${DOMAIN}/api"
else
  echo "Frontend:  http://YOUR_SERVER_IP"
  echo "API:       http://YOUR_SERVER_IP/api"
fi
echo "Service:   ${SERVICE_NAME} (systemctl status ${SERVICE_NAME})"
echo "Install:   ${INSTALL_DIR}"
