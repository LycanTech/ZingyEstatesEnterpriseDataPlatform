#!/usr/bin/env bash
# Reports which platform tools are installed and whether they meet the minimum
# versions in docs/tooling.md. Exit code 1 if a required tool is missing.
set -uo pipefail

missing=0
check() { # name required(yes/no) minimum command...
  local name=$1 required=$2 minimum=$3; shift 3
  if command -v "$1" >/dev/null 2>&1; then
    printf "  %-12s %-8s %s\n" "$name" "ok" "$("$@" 2>&1 | head -1)"
  else
    printf "  %-12s %-8s (need >= %s)\n" "$name" "MISSING" "$minimum"
    [[ $required == yes ]] && missing=1
  fi
}

echo "Core"
check git        yes 2.40   git --version
check terraform  yes 1.6    terraform version
check az         yes 2.60   az version --query '"azure-cli"' -o tsv
check python3    yes 3.10   python3 --version
check docker     yes 24     docker --version
echo "Platform CLIs"
check databricks yes 0.230  databricks --version
check node       yes 20     node --version
check sqlcmd     no  1.8    sqlcmd --version
check java       no  17     java -version
echo "Quality"
check tflint     no  0.53   tflint --version
check checkov    no  3.2    checkov --version
check ruff       no  0.7    ruff --version
check pre-commit no  4.0    pre-commit --version
check pwsh       no  7.4    pwsh --version

exit $missing
