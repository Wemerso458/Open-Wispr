#!/bin/bash
# Standalone check of the OpenRouter transcription call, no mic needed:
# synthesizes a spoken WAV with `say`, sends it exactly like the app does,
# prints the transcript. Run: ./test_api.sh
set -euo pipefail

KEY="${OPENROUTER_API_KEY:-$(grep '^OPENROUTER_API_KEY=' "$HOME/.config/openwispr/.env" 2>/dev/null | cut -d= -f2- || true)}"
if [ -z "$KEY" ]; then
  echo "No API key. Export OPENROUTER_API_KEY or put it in ~/.config/openwispr/.env" >&2
  exit 1
fi
MODEL="${OPENWISPR_MODEL:-$(grep '^MODEL=' "$HOME/.config/openwispr/.env" 2>/dev/null | cut -d= -f2- || true)}"
MODEL="${MODEL:-openai/gpt-4o-mini-transcribe}"

TMP="${TMPDIR:-/tmp}"
say -o "$TMP/openwispr_test.aiff" "Hello, this is a Open Wispr transcription test. One two three."
afconvert -f WAVE -d LEI16@16000 -c 1 "$TMP/openwispr_test.aiff" "$TMP/openwispr_test.wav"

echo "Sending to $MODEL…"
curl -sS https://openrouter.ai/api/v1/audio/transcriptions \
  -H "Authorization: Bearer $KEY" \
  -F "model=$MODEL" \
  -F "file=@$TMP/openwispr_test.wav" \
  | python3 -c 'import json,sys; r=json.load(sys.stdin); print(json.dumps(r,indent=2) if "error" in r else "TRANSCRIPT: "+r["text"])'
