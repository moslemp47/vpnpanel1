# VPN Panel Pro — One-click, GitHub-ready

## Install (Ubuntu/Debian)

**No domain (HTTP):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/scripts/install.sh)   --repo https://github.com/USER/REPO.git --branch main
```

**With domain + HTTPS:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/scripts/install.sh)   --repo https://github.com/USER/REPO.git --branch main   --domain panel.example.com --enable-https --email you@example.com
```

After install, edit `/opt/vpnpanel/src/backend/.env` and fill:
`MARZBAN_API_URL/MARZBAN_TOKEN` and/or `SANAEI_API_URL/SANAEI_TOKEN`.

**Uninstall:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/scripts/uninstall.sh)
```
