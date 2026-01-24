#!/usr/bin/env bash
# =============================================================
# 🚀 Shrine (MDC Flutter) Lab - Auto Script (Task 1 → End)
# ✅ Clone repo → enable web → flutter create → replace 2 files → run
# ✨ Author: ePlus.DEV
# =============================================================
set -euo pipefail

# ------------------------------
# 🎨 Colors
# ------------------------------
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'

log()   { echo -e "${CYAN}➜${RESET} $*"; }
ok()    { echo -e "${GREEN}✔${RESET} $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET} $*"; }
fail()  { echo -e "${RED}✖${RESET} $*"; exit 1; }
title() { echo -e "\n${BOLD}${MAGENTA}==== $* ====${RESET}"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"; }

# ------------------------------
# 📌 Config
# ------------------------------
REPO_URL="https://github.com/material-components/material-components-flutter-codelabs.git"
DEST_BASE="/home/ide-dev"
REPO_DIR="${DEST_BASE}/material-components-flutter-codelabs"
WORK_DIR="${REPO_DIR}/mdc_100_series"

LOGIN_DART="${WORK_DIR}/lib/login.dart"
HOME_DART="${WORK_DIR}/lib/home.dart"
APP_DART="${WORK_DIR}/lib/app.dart"

# ------------------------------
# ✅ Preflight
# ------------------------------
title "Preflight"
need_cmd git
need_cmd flutter
need_cmd perl
ok "git/flutter/perl OK"

mkdir -p "$DEST_BASE"
ok "Destination: $DEST_BASE"

# ------------------------------
# ✅ Task 1 (Manual): Open IDE
# ------------------------------
title "Task 1 (Manual)"
warn "Open the IDE link (Code Server) from Qwiklabs panel in your browser."
warn "This script runs Task 2 → End automatically."

# ------------------------------
# ✅ Task 2: Clone repo
# ------------------------------
title "Task 2 - Clone repo"
if [[ -d "$REPO_DIR/.git" ]]; then
  warn "Repo already exists: $REPO_DIR (skip clone)"
else
  log "Cloning: $REPO_URL"
  git clone "$REPO_URL" "$REPO_DIR"
  ok "Cloned to: $REPO_DIR"
fi

cd "$WORK_DIR"
ok "Working dir: $WORK_DIR"

# ------------------------------
# ✅ Task 2: Enable web + flutter create
# ------------------------------
title "Task 2 - Enable web + flutter create"
log "flutter config --enable-web"
flutter config --enable-web >/dev/null
ok "Web enabled"

log "flutter create ."
flutter create . >/dev/null
ok "flutter create done"

