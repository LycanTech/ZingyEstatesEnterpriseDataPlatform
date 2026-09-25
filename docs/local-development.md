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

To see the metrics in Datadog, set `DD_API_KEY` in `.env` and run:

```bash
docker compose --profile observability up -d datadog-agent
DD_AGENT_HOST=datadog-agent docker compose run --rm platform
```

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
