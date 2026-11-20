#!/usr/bin/env bash
# Push all updates to GitHub
set -e

cd "$(dirname "$0")"
echo "======================================================================"
echo "          TANDAV Autonomous Marine GCS - GitHub Auto-Updater"
echo "======================================================================"
echo "Target: https://github.com/d-i-v-y-a-n-s-h-r-a-i/operator_ui_new.git"
echo ""

git config user.name >/dev/null 2>&1 || git config user.name "divyanshrai"
git config user.email >/dev/null 2>&1 || git config user.email "divyanshrai@users.noreply.github.com"
git lfs install >/dev/null 2>&1 || true

echo "[1/3] Current changes:"
git status --short
echo ""

echo "[2/3] Staging all files..."
git add -A

if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    COMMIT_MSG="Update: $(date) - latest software and telemetry updates"
    echo "Committing: $COMMIT_MSG"
    git commit -m "$COMMIT_MSG"
else
    echo "No new local changes to commit. Ready to push."
fi
echo ""

echo "[3/3] Pushing to GitHub (origin main)..."
git push -u origin main
echo ""
echo "Done!"
