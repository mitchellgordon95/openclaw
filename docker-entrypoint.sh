#!/bin/sh
set -e

STATE_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"

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
      try { cfg = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}
      cfg.gateway = cfg.gateway || {};
      cfg.gateway.controlUi = cfg.gateway.controlUi || {};
      cfg.gateway.controlUi.allowedOrigins = ['$OPENCLAW_ORIGIN'];
      cfg.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
      cfg.gateway.trustedProxies = ['100.64.0.0/10', '10.0.0.0/8', '172.16.0.0/12'];
      if ('$TWILIO_ACCOUNT_SID' && '$TWILIO_AUTH_TOKEN' && '$TWILIO_PHONE_NUMBER') {
        cfg.channels = cfg.channels || {};
        cfg.channels['twilio-sms'] = cfg.channels['twilio-sms'] || {};
        cfg.channels['twilio-sms'].accountSid = '$TWILIO_ACCOUNT_SID';
        cfg.channels['twilio-sms'].authToken = '$TWILIO_AUTH_TOKEN';
        cfg.channels['twilio-sms'].phoneNumber = '$TWILIO_PHONE_NUMBER';
        cfg.channels['twilio-sms'].enabled = true;
      }
      fs.writeFileSync(file, JSON.stringify(cfg, null, 2));
      console.log('Seeded controlUi.allowedOrigins =', ['$OPENCLAW_ORIGIN']);
      console.log('Seeded trustedProxies for Railway internal network');
      if ('$TWILIO_ACCOUNT_SID') console.log('Seeded twilio-sms channel config');
    \"
  "
fi

# Drop to node user and start the gateway.
exec su -s /bin/sh node -c "exec node openclaw.mjs gateway --allow-unconfigured --bind lan"
