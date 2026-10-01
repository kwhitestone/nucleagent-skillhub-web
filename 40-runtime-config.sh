#!/bin/sh
set -eu
: "${SHELL_ORIGIN:?required}" "${FRAME_ANCESTORS:?required}" "${API_UPSTREAM:?required}"
case "$SHELL_ORIGIN" in https://*) ;; *) echo 'SHELL_ORIGIN must use HTTPS' >&2; exit 1;; esac
case "$SHELL_ORIGIN$FRAME_ANCESTORS$API_UPSTREAM" in *\;*|*\{*|*\}*|*\$*|*\"*|*\'*|*\\*) echo 'unsafe runtime configuration' >&2; exit 1;; esac
FRAME_ANCESTORS=$(printf '%s' "$FRAME_ANCESTORS" | tr ',' ' ')
export FRAME_ANCESTORS
for origin in $FRAME_ANCESTORS; do
 case "$origin" in https://*) ;; *) echo 'frame origin must use HTTPS' >&2; exit 1;; esac
 case "$origin" in *\**|*\?*|*\#*|*@*) echo 'frame origin must be exact' >&2; exit 1;; esac
done
envsubst '${FRAME_ANCESTORS} ${API_UPSTREAM}' < /etc/nginx/runtime.conf.template > /etc/nginx/conf.d/default.conf
