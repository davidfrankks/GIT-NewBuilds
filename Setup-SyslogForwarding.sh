#!/usr/bin/env bash
set -e

TARGET_IP="174.79.100.53"
TARGET_PORT="5442"
RSYSLOG_CONF_DIR="/etc/rsyslog.d"
DROPIN_FILE="$RSYSLOG_CONF_DIR/50-forward-auth.conf"

# must run as root
if [[ $EUID -ne 0 ]]; then
  echo "Run as root or via sudo"
  exit 1
fi


# write forwarding rules
cat > "$DROPIN_FILE" <<EOF
# forward auth/authpriv
auth,authpriv.*    @$TARGET_IP:$TARGET_PORT

# forward warnings & errors
*.warning          @$TARGET_IP:$TARGET_PORT
EOF

# verify syntax
rsyslogd -N1

# restart service
systemctl restart rsyslog

# send test messages
logger -p auth.warning "Test auth warning → $TARGET_IP:$TARGET_PORT"
logger -p user.err    "Test user error  → $TARGET_IP:$TARGET_PORT"

echo "Done: forwarding configured and test messages sent."
