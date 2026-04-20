#!/bin/bash
# InvoiceShelf Claude Code engineering harness
# Runs on EC2, reads job details from SSM, executes Claude Code, creates a PR, updates Trello.
set -euo pipefail

LOG_FILE="/tmp/harness.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "=== InvoiceShelf Claude Code Harness starting ==="

# ── Instance metadata (IMDSv2) ───────────────────────────────────────────────
IMDS_TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_REGION=$(curl -sf -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  "http://169.254.169.254/latest/meta-data/placement/region")
INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  "http://169.254.169.254/latest/meta-data/instance-id")

export AWS_DEFAULT_REGION="$AWS_REGION"
log "Instance: $INSTANCE_ID  Region: $AWS_REGION"

# ── Read job from SSM ────────────────────────────────────────────────────────
log "Reading job from SSM: $JOB_PARAM"
JOB_JSON=$(aws ssm get-parameter --name "$JOB_PARAM" --query 'Parameter.Value' --output text)

CARD_ID=$(echo "$JOB_JSON"        | jq -r '.card_id')
CARD_NAME=$(echo "$JOB_JSON"      | jq -r '.card_name')
CARD_DESC=$(echo "$JOB_JSON"      | jq -r '.card_desc')
ITERATION_COMMENT=$(echo "$JOB_JSON" | jq -r '.iteration_comment // ""')
GITHUB_REPO=$(echo "$JOB_JSON"    | jq -r '.github_repo')
ARTIFACTS_BUCKET=$(echo "$JOB_JSON" | jq -r '.artifacts_bucket')
JOB_ID=$(echo "$JOB_JSON"         | jq -r '.job_id')

log "Card: $CARD_NAME ($CARD_ID)  Job: $JOB_ID"

# ── Fetch secrets ────────────────────────────────────────────────────────────
_ssm() { aws ssm get-parameter --name "$1" --with-decryption --query 'Parameter.Value' --output text; }

GITHUB_PAT=$(_ssm "/${PROJECT_NAME}/github/pat")
TRELLO_API_KEY=$(_ssm "/${PROJECT_NAME}/trello/api_key")
TRELLO_API_TOKEN=$(_ssm "/${PROJECT_NAME}/trello/api_token")
CLAUDE_API_KEY=$(_ssm "/${PROJECT_NAME}/claude/api_key")

export ANTHROPIC_API_KEY="$CLAUDE_API_KEY"

# ── Trello helpers ───────────────────────────────────────────────────────────
trello_comment() {
  local text="$1"
  curl -sf -X POST \
    "https://api.trello.com/1/cards/${CARD_ID}/actions/comments" \
    --data-urlencode "key=${TRELLO_API_KEY}" \
    --data-urlencode "token=${TRELLO_API_TOKEN}" \
    --data-urlencode "text=${text}" > /dev/null || true
}

# ── Cleanup and upload ───────────────────────────────────────────────────────
finish() {
  local exit_code=$1
  log "=== Harness finishing (exit $exit_code) ==="

  # Upload logs to S3
  aws s3 cp "$LOG_FILE" \
    "s3://${ARTIFACTS_BUCKET}/logs/${CARD_ID}/${JOB_ID}/harness.log" \
    --region "$AWS_REGION" || true

  # Clean up SSM job param
  aws ssm delete-parameter --name "$JOB_PARAM" --region "$AWS_REGION" 2>/dev/null || true

  log "Shutting down instance"
  sudo shutdown -h now
}
trap 'finish $?' EXIT

# ── Git + gh setup ───────────────────────────────────────────────────────────
git config --global user.email "claude-harness@invoiceshelf.local"
git config --global user.name "Claude Code Harness"
git config --global credential.helper store
echo "https://x-access-token:${GITHUB_PAT}@github.com" > ~/.git-credentials
chmod 600 ~/.git-credentials

echo "$GITHUB_PAT" | gh auth login --with-token
gh auth status

# ── Clone repo ───────────────────────────────────────────────────────────────
WORK_DIR="/workspace/InvoiceShelf"
mkdir -p /workspace
log "Cloning $GITHUB_REPO"
git clone "https://x-access-token:${GITHUB_PAT}@github.com/${GITHUB_REPO}.git" "$WORK_DIR"
cd "$WORK_DIR"

# ── Create feature branch ────────────────────────────────────────────────────
BRANCH_SLUG=$(echo "$CARD_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9]/-/g' \
  | sed 's/--*/-/g' \
  | sed 's/^-//;s/-$//' \
  | cut -c1-40)
BRANCH_NAME="claude/card-${CARD_ID:0:8}-${BRANCH_SLUG}"
git checkout -b "$BRANCH_NAME"
log "Branch: $BRANCH_NAME"

# ── Install project dependencies ─────────────────────────────────────────────
log "Installing PHP dependencies"
composer install --no-interaction --prefer-dist --optimize-autoloader

log "Installing Node dependencies"
npm ci --prefer-offline 2>/dev/null || npm install

# ── Build the Claude Code prompt ─────────────────────────────────────────────
PROMPT_FILE="/tmp/harness_prompt.md"
cat > "$PROMPT_FILE" <<PROMPT
You are an expert Laravel/Vue.js engineer working on the InvoiceShelf codebase.
Read CLAUDE.md first to understand conventions before making any changes.

## Task

**Card:** ${CARD_NAME}
**Card ID:** ${CARD_ID}

### Description

${CARD_DESC}
PROMPT

if [[ -n "$ITERATION_COMMENT" ]]; then
  cat >> "$PROMPT_FILE" <<ITERATION

## Iteration Request

A human has reviewed prior work and is requesting the following changes:

${ITERATION_COMMENT}
ITERATION
fi

cat >> "$PROMPT_FILE" <<INSTRUCTIONS

## Requirements

1. Explore the codebase to understand the affected area before writing code
2. Implement the task following conventions from CLAUDE.md
3. Write feature tests for any new or changed behaviour
4. After modifying PHP files, run: vendor/bin/pint --dirty --format agent
5. Verify tests pass: php artisan test --compact
6. Do NOT commit — the harness handles that

Stay focused on the task. Do not refactor unrelated code.
INSTRUCTIONS

# ── Run Claude Code ──────────────────────────────────────────────────────────
log "Starting Claude Code"
CLAUDE_OUT="/tmp/claude_output.txt"

set +e
claude \
  --dangerously-skip-permissions \
  -p "$(cat "$PROMPT_FILE")" \
  2>&1 | tee "$CLAUDE_OUT"
CLAUDE_EXIT=${PIPESTATUS[0]}
set -e

log "Claude Code exited: $CLAUDE_EXIT"

# Upload Claude output as artifact
aws s3 cp "$CLAUDE_OUT" \
  "s3://${ARTIFACTS_BUCKET}/logs/${CARD_ID}/${JOB_ID}/claude_output.txt" \
  --region "$AWS_REGION" || true

# ── Check for changes ────────────────────────────────────────────────────────
if git diff --quiet && git diff --staged --quiet; then
  log "No file changes produced"
  trello_comment "❌ Claude Code completed but produced no file changes (exit $CLAUDE_EXIT). Job: \`${JOB_ID}\`

Log: \`s3://${ARTIFACTS_BUCKET}/logs/${CARD_ID}/${JOB_ID}/\`"
  exit 0
fi

# ── Commit ───────────────────────────────────────────────────────────────────
git add -A
git commit -m "$(cat <<MSG
feat: ${CARD_NAME}

Automated implementation via Claude Code harness.
Trello card: ${CARD_ID}
Job: ${JOB_ID}
MSG
)"

# ── Push ─────────────────────────────────────────────────────────────────────
git push origin "$BRANCH_NAME"

# ── Create pull request ──────────────────────────────────────────────────────
CLAUDE_SUMMARY=$(tail -200 "$CLAUDE_OUT" | head -100)

PR_BODY="## Summary

Automated implementation by Claude Code harness.

| Field | Value |
|---|---|
| Trello Card | [${CARD_NAME}](https://trello.com/c/${CARD_ID}) |
| Branch | \`${BRANCH_NAME}\` |
| Job ID | \`${JOB_ID}\` |
| Instance | \`${INSTANCE_ID}\` |

## Claude Code output (tail)

\`\`\`
${CLAUDE_SUMMARY}
\`\`\`

---
*To request changes, comment on the Trello card. The harness will open a new iteration.*"

PR_URL=$(gh pr create \
  --title "${CARD_NAME}" \
  --body "$PR_BODY" \
  --base master \
  --head "$BRANCH_NAME" \
  2>&1)

log "PR created: $PR_URL"

# ── Update Trello ─────────────────────────────────────────────────────────────
trello_comment "✅ Claude Code completed successfully!

**Pull Request:** ${PR_URL}
**Branch:** \`${BRANCH_NAME}\`
**Job:** \`${JOB_ID}\`

To request changes, reply to this card with your feedback and the harness will iterate."

log "=== Harness complete ==="
