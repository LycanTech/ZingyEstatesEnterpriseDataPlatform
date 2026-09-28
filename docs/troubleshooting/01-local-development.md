# Local development (`LD-*`)

## LD-01 `docker compose build platform` fails downloading packages

**Symptom:** `pip install` or `apt-get` errors, `Temporary failure in name resolution`, or TLS errors during the image build.

**Cause:** No network or DNS inside Docker, a corporate proxy, or TLS inspection.

**Fix now:**

```bash
docker run --rm python:3.11-slim-bookworm pip download requests -d /tmp   # does basic egress work?
# Behind a proxy, build with:
docker compose build --build-arg HTTP_PROXY=$HTTP_PROXY --build-arg HTTPS_PROXY=$HTTPS_PROXY platform
```

With TLS inspection, add the corporate root CA to the image (`COPY ca.crt /usr/local/share/ca-certificates/ && update-ca-certificates`).

**Prevent:** Document proxy settings in `.env` and Docker Desktop → Settings → Resources → Proxies.

## LD-02 First Spark run hangs or fails fetching Delta jars (`:: resolving dependencies ::`)

**Symptom:** Ivy output followed by `download failed` or a long hang the first time Spark starts.

**Cause:** Delta jars are downloaded from Maven Central at runtime. That fails on blocked or flaky networks, or when the Ivy cache is corrupted.

**Fix now:**

```bash
docker volume rm zingyestatesenterprisedataplatform_ivy-cache   # clear a corrupt cache
docker compose build --no-cache platform                       # the image pre-fetches the jars
```

**Prevent:** Keep the pre-fetch step in `docker/platform.Dockerfile`. In locked-down networks, mirror Maven Central and set `spark.jars.repositories`.

## LD-03 `JAVA_GATEWAY_EXITED` or Java not found running pytest natively

**Symptom:** `PySparkRuntimeError: [JAVA_GATEWAY_EXITED] Java gateway process exited before sending its port number`, or Spark tests are shown as **skipped**.

**Cause:** Java 17 is missing, or `JAVA_HOME` points to a different Java version (Spark 3.5 supports 8, 11 and 17).

**Fix now:**

```bash
java -version                         # must be 17
export JAVA_HOME=/path/to/jdk-17
# or skip native setup entirely:
docker compose run --rm platform pytest
```

**Prevent:** Use the dev container or Docker for Spark work. `tests/conftest.py` skips Spark tests when Java is absent, so check that skipped count.

## LD-04 Spark on native Windows: `winutils.exe`, `HADOOP_HOME` or `UnsatisfiedLinkError`

**Symptom:** Errors about `winutils`, `NativeIO$Windows`, or file-permission failures writing Delta tables.

**Cause:** Hadoop's local filesystem needs Windows native binaries.

**Fix now:** Don't run Spark natively on Windows. Use `docker compose run --rm platform` or the dev container.

**Prevent:** [docs/local-development.md](../local-development.md) recommends Docker on Windows.

## LD-05 Shell scripts fail with `bash\r: No such file or directory`

**Symptom:** `/usr/bin/env: 'bash\r': No such file or directory`, or `$'\r': command not found` in containers or CI.

**Cause:** A script was saved with CRLF line endings, often by a Windows editor or a checkout with `core.autocrlf=true`.

**Fix now:**

```bash
git add --renormalize . && git commit -m "Normalize line endings"
# or for one file:
sed -i 's/\r$//' scripts/deploy-synapse.sh
```

**Prevent:** `.gitattributes` forces LF (`* text=auto eol=lf`). Set `git config --global core.autocrlf input` and keep editors on LF (`.editorconfig`).

## LD-06 A file shows as binary on GitHub or contains null bytes

**Symptom:** GitHub shows "binary file", `file README.md` reports `data`, or diffs show `\0` characters.

**Cause:** Windows PowerShell 5.1 `>`, `>>` and `Out-File` write UTF-16. This happened in this repo when GitHub's `echo "# ..." >> README.md` quick-start was run in PowerShell.

**Fix now:**

```bash
file README.md                       # confirm
# Remove the UTF-16 part, or re-save the file as UTF-8 in VS Code (status bar → encoding → Save with Encoding → UTF-8)
```

**Prevent:** In PowerShell use `Add-Content -Encoding utf8` / `Set-Content -Encoding utf8`, or use Git Bash. The `end-of-file-fixer` and `check-added-large-files` pre-commit hooks catch some cases.

## LD-07 OneDrive sync conflicts, locked files, or a huge sync backlog

**Symptom:** `The process cannot access the file because it is being used by another process`, duplicate files named `-DESKTOP-XXXX`, Terraform `.terraform/` or `node_modules/` syncing for hours, or files that "changed on disk" unexpectedly.

**Cause:** The repo lives under `OneDrive\Desktop`, so OneDrive syncs every build artifact and briefly locks files.

**Fix now:** Pause OneDrive sync while building, or move the repo:

```powershell
git clone https://github.com/LycanTech/ZingyEstatesEnterpriseDataPlatform.git C:\src\ZingyEstatesEnterpriseDataPlatform
```

**Prevent:** Keep Git repos outside OneDrive (for example `C:\src`). Git is the backup.

## LD-08 `docker compose run` can't find `zingyestates` (`ModuleNotFoundError`)

**Symptom:** `ModuleNotFoundError: No module named 'zingyestates'`.

**Cause:** `PYTHONPATH` isn't set (native runs), or the repo isn't mounted at `/workspace`.

**Fix now:**

```bash
export PYTHONPATH=$PWD/databricks/src      # native
pip install -e databricks                  # or install the package in editable mode
```

**Prevent:** Use the compose service (sets `PYTHONPATH`) or the dev container (`containerEnv`).

## LD-09 Paths are mangled when running Docker from Git Bash on Windows

**Symptom:** Paths like `C:/Program Files/Git/workspace`, or `-w /workspace` being rewritten.

**Cause:** MSYS path conversion in Git Bash.

**Fix now:** Prefix the command with `MSYS_NO_PATHCONV=1`, or use `$(pwd -W)` for host paths:

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/repo" -w /repo rhysd/actionlint:latest
```

**Prevent:** Use PowerShell, WSL, or the dev container for Docker commands.

## LD-10 Port 8888 already in use when starting Jupyter

**Symptom:** `Bind for 0.0.0.0:8888 failed: port is already allocated`.

**Fix now:** Stop the other process, or change the host port in `docker-compose.yml` (`"8889:8888"`).

**Prevent:** None needed. This is environment-specific.

## LD-11 Local run output differs from Databricks

**Symptom:** A test passes locally but the job fails on Databricks, or the reverse.

**Cause:** The local runtime (`pyspark`/`delta-spark` in `requirements-dev.txt`) has drifted from the Databricks runtime (`spark_version` in `databricks/resources/*.yml`). Typical triggers are ANSI mode, which is default on in newer runtimes, and behaviour differences between Python versions.

**Fix now:** Confirm the versions match. DBR 15.4 LTS uses Spark 3.5, Delta 3.2 and Python 3.11. Reproduce with the same versions, or run on a dev cluster: `make bundle-deploy ENV=dev`.

**Prevent:** Upgrade the runtime and the pins together ([AGE-01](12-aging-and-maintenance.md#age-01-databricks-runtime-154-lts-reaches-end-of-support)). Dependabot is configured to ignore `pyspark`/`delta-spark`.

## LD-12 Pre-commit hooks fail or are slow on first run

**Symptom:** `pre-commit` downloads environments, then `terraform_tflint` or `gitleaks` fails.

**Cause:** First-run hook installation. TFLint needs `tflint --init` for the azurerm plugin.

**Fix now:**

```bash
pre-commit clean && pre-commit install && tflint --init --config .tflint.hcl
pre-commit run --all-files
```

**Prevent:** The dev container runs `pre-commit install` in `post-create.sh`.

## LD-13 Dev container build fails

**Symptom:** A feature install fails (Terraform, Azure CLI, Java) or `post-create.sh` errors.

**Cause:** A feature version was yanked, there's no network, or a download URL for `go-sqlcmd` or the Databricks CLI changed.

**Fix now:** **Dev Containers: Rebuild Without Cache**. Check the failing URL in `.devcontainer/post-create.sh` and bump the version.

**Prevent:** Keep the pinned versions in `post-create.sh` in step with `pipelines/variables/common.yml` and the workflows.

## LD-14 `.local-lake` grows large or contains stale data

**Symptom:** Demo results look odd after changing the schema, or disk use grows.

**Cause:** The Delta tables from earlier runs keep their old schema and history.

**Fix now:** `make clean`, or `rm -rf .local-lake`, then rerun the demo.

**Prevent:** None needed. `.local-lake` is disposable and git-ignored.

## LD-15 Datadog Agent install on Windows fails: `An exception occurred during a WebClient request`

**Symptom:** Running Datadog's Windows install command fails on the first line:

```
(New-Object System.Net.WebClient).DownloadFile('https://install.datadoghq.com/datadog-installer-x86_64.exe', 'C:\Windows\SystemTemp\datadog-installer-x86_64.exe');
Exception calling "DownloadFile" with "2" argument(s): "An exception occurred during a WebClient request."
```

**Cause:** PowerShell isn't elevated. The download works, but the destination `C:\Windows\SystemTemp` is admin-only, so the real error (`Access to the path ... is denied`) is hidden inside `WebClient`. Less common causes are no network access to `install.datadoghq.com`, a proxy, or TLS 1.2 disabled on old Windows PowerShell 5.1 installs.

**Fix now:**

```powershell
# 1. Check elevation. Must print True. If not: Start -> PowerShell -> right-click -> Run as administrator
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# 2. If it still fails, find the real error:
Invoke-WebRequest -Uri 'https://install.datadoghq.com/datadog-installer-x86_64.exe' -Method Head -UseBasicParsing
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12   # old PS 5.1 only
```

Then paste Datadog's **full** install command (Datadog → Integrations → Agent → Windows) in the elevated window. The download line is only the first part; the rest sets the API key and site. The command puts the API key on the command line, so clear the PowerShell history afterwards:

```powershell
Remove-Item (Get-PSReadLineOption).HistorySavePath
```

**Prevent:** The platform doesn't need a Windows host agent. Local runs use the agent container (`docker compose --profile observability up -d datadog-agent`, with `DD_API_KEY` in the git-ignored `.env`), and Azure is monitored through the Datadog Azure integration. Install the host agent only to monitor the workstation itself.
