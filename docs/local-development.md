# Local development

## Option A: Docker only (Windows, macOS, Linux)

You need Docker Desktop and nothing else.

```bash
docker compose build platform                  # once, about 3 minutes
docker compose run --rm platform               # end-to-end demo -> ./.local-lake
docker compose run --rm platform pytest        # all tests, including Spark
docker compose --profile notebooks up jupyter  # http://localhost:8888
```

The demo generates about 700 synthetic source records with deliberate defects. It runs bronze, silver, and gold, then prints:

- the row count for each zone,
- the data-quality rejections and duplicates for each entity, grouped by failed rule,
- the top markets from `gold.agg_market_monthly`.

### View the demo's metrics in Datadog

The `datadog-agent` container is the Datadog **Agent**. It has no UI of its own; it forwards metrics to your Datadog account, and you view them on the Datadog website.

**1. Configure `.env`** (git-ignored, so the key is never committed):

```bash
cp .env.example .env
```

```
DD_API_KEY=<API key from Datadog → Organization Settings → API Keys>   # an API key, not an application key
DD_SITE=datadoghq.com        # match your login URL: datadoghq.eu, us3.datadoghq.com, us5.datadoghq.com, ...
DD_AGENT_HOST=datadog-agent  # makes the demo send metrics to the Agent container
```

**2. Start the Agent and check it's connected:**

```bash
docker compose --profile observability up -d datadog-agent
docker compose exec datadog-agent agent status     # API key valid, DogStatsD running
```

**3. Run the demo:**

```bash
docker compose run --rm platform
```

The output should include `Metrics backend: dogstatsd`. If it says `Metrics backend: log`, `DD_AGENT_HOST` isn't set.

**4. View the metrics** (they usually appear within 1–3 minutes):

- **Metrics → Explorer:** search for `zingyestates.`, filter "from" `env:local`, and group by `entity` or `pipeline`. Useful metrics:
  - `zingyestates.data.quality.records_processed`
  - `zingyestates.data.quality.rejection_rate`
  - `zingyestates.data.quality.duplicates`
  - `zingyestates.data.pipeline.duration_seconds`
  - `zingyestates.data.freshness_minutes`
- **Metrics → Summary:** lists every `zingyestates.*` metric and its tags.
- **Dashboards → New Dashboard:** add widgets such as `avg:zingyestates.data.quality.rejection_rate{env:local} by {entity}`.

The Terraform-managed dashboard filters on `env:dev|qa|uat|prod`, so local runs (`env:local`) don't appear on it.

**5. Stop the Agent:**

```bash
docker compose --profile observability down
```

| Problem | Fix |
|---|---|
| Agent status shows the API key as invalid | Wrong key or `DD_SITE`. Fix `.env`, then run `docker compose --profile observability up -d --force-recreate datadog-agent` |
| Demo prints `Metrics backend: log` | Add `DD_AGENT_HOST=datadog-agent` to `.env` |
| Many `Error submitting packet: [Errno -2] Name or service not known` warnings, and the demo is slow | `DD_AGENT_HOST` is set but the Agent isn't running. Start it (step 2) or clear `DD_AGENT_HOST` in `.env` |
| Nothing in Explorer after 5 minutes | Check the time range and that you're logged in to the same site as `DD_SITE` |
| Installing the Datadog Agent on Windows fails | You don't need it for this. See [LD-15](troubleshooting/01-local-development.md#ld-15-datadog-agent-install-on-windows-fails-an-exception-occurred-during-a-webclient-request) |

## Option B: dev container (full toolchain)

Open the repo in VS Code, then run **Dev Containers: Reopen in Container**. `.devcontainer/post-create.sh` installs every tool listed in [tooling.md](tooling.md) and runs `scripts/check-prereqs.sh`. Then use `make help`.

## Option C: native

Install Python 3.11, Java 17, Terraform, the Azure CLI, Node 20, and the Databricks CLI. Then:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt -e databricks
make test
python -m zingyestates.local_run
```

## Common tasks

| Task | Command |
|---|---|
| Lint and format | `make lint` / `make fmt` |
| Validate Terraform offline | `make tf-validate` |
| Plan an environment | `az login` then `make tf-plan ENV=qa` |
| Validate ADF offline | `make adf-validate` |
| Deploy your own dev copy of the bundle | `make bundle-deploy ENV=dev STORAGE=<account>` (development mode prefixes the job with your name) |
| Rerun one step locally | `python -c "from zingyestates.cli import silver_main; silver_main(['--env','local','--run-date','2026-09-25'])"` |

## Adding a new source entity

1. Add an `Entity` to `databricks/src/zingyestates/entities.py`.
2. Add its rules to `RULES` in `quality.py`. `test_every_entity_has_quality_rules` fails if you forget.
3. Add rows to `sample_data.generate`.
4. Add the ADF copy: a `crm_tables` entry in `pl_ingest_crm`, or a new pipeline.
5. Use it in `gold.py`. If it's served from the dedicated pool, add a `V###` staging-table migration and a `dw.load_config` row.
