#!/usr/bin/env bash
# Installs the tools that have no dev-container feature.
set -euo pipefail

echo "==> Python dependencies"
pip install --user -r requirements-dev.txt checkov==3.2.296
pip install --user -e databricks

echo "==> Databricks CLI (Asset Bundles)"
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/v0.230.0/install.sh | sudo sh

echo "==> go-sqlcmd (Synapse deployments)"
SQLCMD_VERSION=1.8.0
curl -fsSL "https://github.com/microsoft/go-sqlcmd/releases/download/v${SQLCMD_VERSION}/sqlcmd-linux-amd64.tar.bz2" \
  | sudo tar -xj -C /usr/local/bin sqlcmd

echo "==> ADF build utilities"
(cd adf && npm ci --no-audit --no-fund)

echo "==> Git hooks"
pre-commit install || true

bash scripts/check-prereqs.sh
