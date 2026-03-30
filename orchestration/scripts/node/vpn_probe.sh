#!/bin/bash
systemctl is-active --quiet wg-quick@wg0 \
    && wg show wg0 latest-handshakes 2>/dev/null \
    | grep -Eq '^[^[:space:]]+[[:space:]][1-9][0-9]*$' \
    && echo VPN_READY || echo VPN_WAITING
