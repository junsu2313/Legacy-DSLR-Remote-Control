#!/bin/sh
set -eu

if [ $# -lt 1 ]; then
  echo "usage: $0 <jpeg-path> [base-url] [camera-id]" >&2
  exit 1
fi

JPEG_PATH="$1"
BASE_URL="${2:-https://underlab.work}"
CAMERA_ID="${3:-d810}"
TOKEN="${CAMERA_UPLOAD_TOKEN:-}"

if [ ! -r "$JPEG_PATH" ]; then
  echo "jpeg not readable: $JPEG_PATH" >&2
  exit 1
fi

FILENAME="$(basename "$JPEG_PATH")"
CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

set -- \
  -X POST \
  -H "Content-Type: image/jpeg" \
  -H "X-File-Name: $FILENAME" \
  -H "X-Camera-Id: $CAMERA_ID" \
  -H "X-Captured-At: $CAPTURED_AT"

if [ -n "$TOKEN" ]; then
  set -- "$@" -H "Authorization: Bearer $TOKEN"
fi

exec curl \
  "$@" \
  --data-binary "@$JPEG_PATH" \
  "$BASE_URL/api/camera/upload"
