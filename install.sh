#!/usr/bin/env bash
set -e

# ==============================================================================
# Oracle Ampere A1 Autopilot - Systemd Service Installer
# ==============================================================================

BASE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$BASE/oracle-hunter.sh"
SERVICE_NAME="oracle-a1-autopilot"

export PATH="$HOME/.local/bin:$HOME/lib/oracle-cli/bin:/usr/local/bin:$PATH"

echo "=== Oracle A1 Autopilot Installer ==="
echo

# 1. Verify script existence
if [[ ! -f "$SCRIPT" ]]; then
    echo "[-] Error: $SCRIPT not found."
    exit 1
fi
chmod +x "$SCRIPT"

# 2. Check for OCI CLI
if ! command -v oci >/dev/null 2>&1; then
    echo "[-] OCI CLI was not detected in PATH."
    echo "    Install it using:"
    echo '    bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"'
    echo "    Then configure it by running: oci setup config"
    exit 1
fi

echo "[+] OCI CLI found: $(command -v oci)"

# 3. Determine installation mode (User vs System-wide)
if [[ $EUID -eq 0 ]]; then
    # Running as root: Install system-wide service
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    TARGET_USER="${SUDO_USER:-root}"
    TARGET_HOME="$(eval echo "~$TARGET_USER")"

    echo "[*] Installing as system-wide service for user '$TARGET_USER'..."

    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Oracle Ampere A1 Always Free Autopilot Hunter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
WorkingDirectory=$BASE
ExecStart=$SCRIPT
Restart=always
RestartSec=10
Environment=HOME=$TARGET_HOME
Environment=PATH=$TARGET_HOME/.local/bin:$TARGET_HOME/lib/oracle-cli/bin:/usr/local/bin:/usr/bin:/bin
Environment=SUPPRESS_LABEL_WARNING=True

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"

    echo
    echo "[+] Successfully installed system-wide service!"
    echo
    echo "Next steps:"
    echo "  1. Edit configuration : nano $SCRIPT"
    echo "  2. Start hunter       : sudo systemctl start $SERVICE_NAME"
    echo "  3. Check live logs    : sudo journalctl -u $SERVICE_NAME -f"
    echo "  4. Stop hunter        : sudo systemctl stop $SERVICE_NAME"
else
    # Running as non-root user: Install user-level systemd service
    USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
    SERVICE_FILE="$USER_SYSTEMD_DIR/${SERVICE_NAME}.service"

    echo "[*] Installing as user-level systemd service (no root/sudo needed)..."
    mkdir -p "$USER_SYSTEMD_DIR"

    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Oracle Ampere A1 Always Free Autopilot Hunter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$BASE
ExecStart=$SCRIPT
Restart=always
RestartSec=10
Environment=HOME=$HOME
Environment=PATH=$HOME/.local/bin:$HOME/lib/oracle-cli/bin:/usr/local/bin:/usr/bin:/bin
Environment=SUPPRESS_LABEL_WARNING=True

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME"

    # Enable linger so service keeps running 24/7 after SSH logout
    if command -v loginctl >/dev/null 2>&1; then
        loginctl enable-linger "$USER" 2>/dev/null || true
    fi

    echo
    echo "[+] Successfully installed user-level service!"
    echo
    echo "Next steps:"
    echo "  1. Edit configuration : nano $SCRIPT"
    echo "  2. Start hunter       : systemctl --user start $SERVICE_NAME"
    echo "  3. Check live logs    : journalctl --user -u $SERVICE_NAME -f"
    echo "  4. Stop hunter        : systemctl --user stop $SERVICE_NAME"
fi

echo
echo "Remember to fill in COMPARTMENT_ID and SUBNET_ID in $SCRIPT before starting!"
