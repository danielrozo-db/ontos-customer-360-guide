#!/usr/bin/env bash
# =============================================================================
# 09_upload_docs.sh — Attach the contract documentation (Markdown + PDF) to the
#                     Customer 360 Profile data contract in Ontos
# =============================================================================
# Ontos stores per-entity documents via a generic metadata endpoint:
#   POST /api/entities/{entity_type}/{entity_id}/documents   (multipart/form-data)
#     fields: title (required), short_description (optional), file (required)
# For a data contract the entity_type is "data_contract" and the entity_id is
# the Ontos contract UUID (CONTRACT_ID, saved by 05_contract.sh).
#
# This script uploads both docs generated under ../assets, is idempotent (skips
# a file already attached under the same original filename), and then reads the
# document list back to prove the uploads landed.
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
load_state
: "${CONTRACT_ID:?run 05_contract.sh first (no CONTRACT_ID in state)}"

ENTITY_TYPE="data_contract"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/assets"

MD_FILE="$ASSETS_DIR/customer_360_profile_data_contract.md"
PDF_FILE="$ASSETS_DIR/customer_360_profile_data_contract.pdf"

DOCS_PATH="/api/entities/$ENTITY_TYPE/$CONTRACT_ID/documents"

# upload_doc FILE TITLE DESCRIPTION CONTENT_TYPE
upload_doc() {
  local file="$1" title="$2" desc="$3" ctype="$4"
  local base; base="$(basename "$file")"

  if [[ ! -f "$file" ]]; then
    echo "    ERROR: file not found: $file" >&2
    return 1
  fi

  # Idempotency: is a document with this original filename already attached?
  local existing
  existing="$(api_get "$DOCS_PATH" \
    | jq -r --arg f "$base" 'map(select((.original_filename // "")==$f)) | (.[0].id // empty)')"
  if [[ -n "$existing" ]]; then
    echo "    reusing $base (already attached, id=$existing)"
    printf '%s' "$existing"; return 0
  fi

  # Multipart upload. title/short_description are form fields; file carries type.
  local tmp code
  tmp="$(mktemp)"
  code="$(curl -sS -o "$tmp" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -F "title=$title" \
    -F "short_description=$desc" \
    -F "file=@$file;type=$ctype" \
    "$BASE_URL$DOCS_PATH")"
  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    echo "    ERROR: HTTP $code uploading $base" >&2
    cat "$tmp" >&2; echo >&2
    rm -f "$tmp"; return 1
  fi
  local id; id="$(jq -r '.id // empty' "$tmp")"
  rm -f "$tmp"
  echo "    uploaded $base (id=$id)"
  printf '%s' "$id"
}

echo "==> Attaching contract docs to $ENTITY_TYPE/$CONTRACT_ID"
MD_ID="$(upload_doc "$MD_FILE"  "Customer 360 Profile — Data Contract (Markdown)" \
                    "Structured documentation of the Customer 360 Profile data contract (source Markdown)." \
                    "text/markdown")"
PDF_ID="$(upload_doc "$PDF_FILE" "Customer 360 Profile — Data Contract (PDF)" \
                     "Structured documentation of the Customer 360 Profile data contract (rendered PDF)." \
                     "application/pdf")"

echo "==> Verifying documents on the contract"
DOCS_JSON="$(api_get "$DOCS_PATH")"
echo "$DOCS_JSON" | jq -r '
  if length == 0 then "    (no documents found)"
  else .[] | "    - \(.original_filename)  [\(.content_type // "?")]  \(.size_bytes // 0) bytes  title=\"\(.title)\"  id=\(.id)"
  end'

MD_OK="$(  echo "$DOCS_JSON" | jq -r --arg f "$(basename "$MD_FILE")"  'any(.[]?; (.original_filename // "")==$f)')"
PDF_OK="$( echo "$DOCS_JSON" | jq -r --arg f "$(basename "$PDF_FILE")" 'any(.[]?; (.original_filename // "")==$f)')"

echo "==> Result: markdown=$MD_OK  pdf=$PDF_OK"
if [[ "$MD_OK" == "true" && "$PDF_OK" == "true" ]]; then
  echo "==> SUCCESS: both documents are attached to contract $CONTRACT_ID"
else
  echo "==> INCOMPLETE: one or both documents are missing (see errors above)" >&2
  exit 1
fi
