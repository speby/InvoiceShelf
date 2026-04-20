#!/bin/bash
# Packer provisioner: installs all tools needed by the Claude Code harness on Amazon Linux 2023
set -euo pipefail

echo "==> System update"
sudo dnf update -y

echo "==> Installing base utilities"
sudo dnf install -y git jq curl wget unzip tar make gcc-c++

# ── Node.js 20 ───────────────────────────────────────────────────────────────
echo "==> Installing Node.js 20"
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs
node --version
npm --version

# ── Claude Code CLI ──────────────────────────────────────────────────────────
echo "==> Installing Claude Code CLI"
sudo npm install -g @anthropic-ai/claude-code
claude --version

# ── GitHub CLI ───────────────────────────────────────────────────────────────
echo "==> Installing GitHub CLI"
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install -y gh
gh --version

# ── PHP (Amazon Linux 2023 ships PHP 8.2) ────────────────────────────────────
echo "==> Installing PHP"
sudo dnf install -y \
  php \
  php-cli \
  php-common \
  php-mbstring \
  php-xml \
  php-pdo \
  php-sqlite3 \
  php-zip \
  php-curl \
  php-bcmath \
  php-tokenizer \
  php-dom \
  php-fileinfo \
  php-intl
php --version

# ── Composer ────────────────────────────────────────────────────────────────
echo "==> Installing Composer"
curl -sS https://getcomposer.org/installer \
  | sudo php -- --install-dir=/usr/local/bin --filename=composer
composer --version

# ── AWS CLI (pre-installed on AL2023, but ensure it's current) ───────────────
echo "==> AWS CLI version"
aws --version

# ── Warm up npm cache for faster Claude Code runs ────────────────────────────
echo "==> Pre-warming Claude Code node_modules"
# Claude Code resolves its own deps at first run; trigger once here
HOME=/root claude --version 2>/dev/null || true

echo "==> Install complete"
