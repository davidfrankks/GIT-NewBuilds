#!/usr/bin/env bash
set -e

# prompt
read -p "Enter the desired static IP address (with CIDR, e.g. 192.168.1.200/24): " USER_IP
read -p "Enter the default gateway IP address: " GATEWAY

# variables
INTERFACE="ens18"                       # adjust if needed
STATIC_IP="$USER_IP"
DNS="$GATEWAY,8.8.8.8"                  # default gateway + Google DNS

echo "Configured Static IP: $STATIC_IP"
echo "Configured Gateway: $GATEWAY"
echo "Configured DNS: $DNS"

# backup existing Netplan config
NETPLAN_DIR="/etc/netplan"
SRC_FILE="$NETPLAN_DIR/01-netcfg.yaml"
BACKUP_FILE="$NETPLAN_DIR/backup_$(date +%Y%m%d%H%M%S).yaml"
if [ -f "$SRC_FILE" ]; then
  echo "Backing up existing Netplan config to $BACKUP_FILE"
  cp "$SRC_FILE" "$BACKUP_FILE"
fi

# generate new Netplan YAML with routes
cat > "$SRC_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      addresses:
        - $STATIC_IP
      routes:
        - to: 0.0.0.0/0
          via: $GATEWAY
      nameservers:
        addresses: [$DNS]
EOF

# apply and report
echo "Applying Netplan configuration..."
if netplan apply; then
  echo "Netplan applied successfully."
else
  echo "Error: failed to apply Netplan. Check $SRC_FILE for syntax errors."
  exit 1
fi
