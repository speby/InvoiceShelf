#!/bin/bash
# Registers (or re-registers) the Trello webhook pointing at the API Gateway URL.
# Run after `terraform apply` once the API Gateway URL is available.
#
# Usage:
#   TRELLO_API_KEY=xxx TRELLO_API_TOKEN=xxx CALLBACK_URL=https://... ./register_webhook.sh
#
# Or let it pull credentials from AWS SSM (requires aws CLI + correct IAM):
#   AWS_REGION=us-east-1 ./register_webhook.sh
set -euo pipefail

BOARD_ID="${TRELLO_BOARD_ID:-jFWLnGp4}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-invoiceshelf}"

# ── Resolve credentials ──────────────────────────────────────────────────────
if [[ -z "${TRELLO_API_KEY:-}" ]]; then
  echo "Fetching Trello API key from SSM..."
  TRELLO_API_KEY=$(aws ssm get-parameter \
    --name "/${PROJECT_NAME}/trello/api_key" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text \
    --region "$AWS_REGION")
fi

if [[ -z "${TRELLO_API_TOKEN:-}" ]]; then
  echo "Fetching Trello API token from SSM..."
  TRELLO_API_TOKEN=$(aws ssm get-parameter \
    --name "/${PROJECT_NAME}/trello/api_token" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text \
    --region "$AWS_REGION")
fi

# ── Resolve callback URL ─────────────────────────────────────────────────────
if [[ -z "${CALLBACK_URL:-}" ]]; then
  echo "Fetching API Gateway URL from Terraform outputs..."
  CALLBACK_URL=$(cd "$(dirname "$0")/../terraform" && terraform output -raw webhook_url)
fi

echo ""
echo "Board ID    : $BOARD_ID"
echo "Callback URL: $CALLBACK_URL"
echo ""

# ── List existing webhooks and delete any stale ones for this board ──────────
echo "Checking for existing webhooks on board $BOARD_ID..."
EXISTING=$(curl -sf \
  "https://api.trello.com/1/tokens/${TRELLO_API_TOKEN}/webhooks?key=${TRELLO_API_KEY}" \
  | jq -r ".[] | select(.idModel == \"$BOARD_ID\") | .id")

if [[ -n "$EXISTING" ]]; then
  echo "Found existing webhooks:"
  echo "$EXISTING"
  read -rp "Delete existing webhooks before registering? [y/N] " confirm
  if [[ "${confirm,,}" == "y" ]]; then
    while IFS= read -r wid; do
      echo "Deleting webhook $wid..."
      curl -sf -X DELETE \
        "https://api.trello.com/1/webhooks/${wid}?key=${TRELLO_API_KEY}&token=${TRELLO_API_TOKEN}"
    done <<< "$EXISTING"
  fi
fi

# ── Register new webhook ─────────────────────────────────────────────────────
echo ""
echo "Registering webhook..."
RESPONSE=$(curl -sf -X POST \
  "https://api.trello.com/1/webhooks" \
  --data-urlencode "key=${TRELLO_API_KEY}" \
  --data-urlencode "token=${TRELLO_API_TOKEN}" \
  --data-urlencode "callbackURL=${CALLBACK_URL}" \
  --data-urlencode "idModel=${BOARD_ID}" \
  --data-urlencode "description=InvoiceShelf Claude Code Harness" \
  --data-urlencode "active=true")

WEBHOOK_ID=$(echo "$RESPONSE" | jq -r '.id')
echo ""
echo "==> Webhook registered successfully"
echo "    ID         : $WEBHOOK_ID"
echo "    Callback   : $CALLBACK_URL"
echo "    Board      : $BOARD_ID"
echo ""
echo "Move a card to 'Ready for Claude Code' to test the integration."
