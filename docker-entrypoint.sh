#!/bin/sh
set -e

STATE_DIR="${OPENCLAW_STATE_DIR:-${OPENCLAW_HOME:+$OPENCLAW_HOME/.openclaw}}"
STATE_DIR="${STATE_DIR:-/home/node/.openclaw}"

# Fix volume permissions (runs as root in the entrypoint).
mkdir -p "$STATE_DIR"
chown -R node:node "$STATE_DIR"

# Seed controlUi.allowedOrigins if OPENCLAW_ORIGIN is set.
# Idempotent — overwrites on every start so env var changes take effect.
if [ -n "$OPENCLAW_ORIGIN" ]; then
  su -s /bin/sh node -c "
    node -e \"
      const fs = require('fs');
      const dir = '$STATE_DIR';
      const file = dir + '/openclaw.json';
      let cfg = {};
      if (fs.existsSync(file)) { cfg = JSON.parse(fs.readFileSync(file, 'utf8')); }
      cfg.gateway = cfg.gateway || {};
      cfg.gateway.controlUi = cfg.gateway.controlUi || {};
      cfg.gateway.controlUi.allowedOrigins = ['$OPENCLAW_ORIGIN'];
      cfg.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
      cfg.gateway.trustedProxies = ['100.64.0.0/10', '10.0.0.0/8', '172.16.0.0/12'];
      fs.writeFileSync(file, JSON.stringify(cfg, null, 2));
      console.log('Seeded gateway config for Railway');
    \"
  "
fi

# Symlink persistent SSH keys into the node user's home if they exist.
if [ -d "$STATE_DIR/.ssh" ]; then
  mkdir -p /home/node/.ssh
  for key in "$STATE_DIR/.ssh"/*; do
    [ -f "$key" ] && ln -sf "$key" "/home/node/.ssh/$(basename "$key")"
  done
  chown -h node:node /home/node/.ssh /home/node/.ssh/*
  chmod 700 /home/node/.ssh
fi

# Symlink persistent Go binaries (e.g. wacli) into PATH.
if [ -d "$STATE_DIR/gopath/bin" ]; then
  for bin in "$STATE_DIR/gopath/bin"/*; do
    [ -f "$bin" ] && ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"
  done
fi

# Symlink persistent Railway CLI config if it exists.
if [ -d "$STATE_DIR/.railway" ]; then
  mkdir -p /home/node/.railway
  ln -sf "$STATE_DIR/.railway/config.json" /home/node/.railway/config.json
  chown -h node:node /home/node/.railway /home/node/.railway/config.json
fi

# Drop to node user and start the gateway.
exec su -s /bin/sh node -c "exec node openclaw.mjs gateway --allow-unconfigured --bind lan"
