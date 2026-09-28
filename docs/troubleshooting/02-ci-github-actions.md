# CI and GitHub (`CI-*`)

Get the failing log first:

```bash
gh run list --workflow ci.yml --limit 5
gh run view <run-id> --log-failed
gh run rerun <run-id> --failed        # after fixing a flaky or external cause
```

## CI-01 `terraform fmt -check` fails

**Symptom:** The `fmt` step exits 3 and lists file names.

**Cause:** Terraform files weren't formatted before commit.

**Fix now:** `terraform -chdir=terraform fmt -recursive && terraform -chdir=datadog fmt -recursive`, then commit.

**Prevent:** The `terraform_fmt` pre-commit hook, or format-on-save (set in the dev container).

## CI-02 `terraform validate` fails after a code change

**Symptom:** `Unsupported argument`, `Missing required argument`, or `Reference to undeclared resource`.

**Cause:** A typo, a module input that was renamed on one side only, or a provider schema change.

**Fix now:** Reproduce it with `make tf-validate`. The error names the file and line.

**Prevent:** Run `make tf-validate` before pushing.

## CI-03 `terraform init` fails: `locked provider ... does not match configured version constraint`

**Symptom:** `locked provider registry.terraform.io/hashicorp/azurerm 5.7.0 does not match configured version constraint ~> 4.14, ~> 5.6`.

**Cause:** Two `required_providers` blocks disagree. Usually Dependabot bumped the root `terraform/versions.tf` while a module pinned an incompatible range. This happened on PR #8.

**Fix now:** Modules must declare only a minimum (`version = ">= 4.14"`). Check them all:

```bash
grep -rn 'version *=' terraform/modules/*/versions.tf
terraform -chdir=terraform init -backend=false -upgrade && terraform -chdir=terraform validate
```

Then fix any schema errors the new major version reports ([TF-11](04-terraform-and-azure.md#tf-11-provider-major-upgrade-breaks-validate-or-plan)).

**Prevent:** Only the root module sets the upper bound. Review Dependabot major bumps before merging.

## CI-04 TFLint fails after a TFLint or ruleset update

**Symptom:** New warnings such as `terraform_required_providers`, `terraform_unused_declarations`, or azurerm-specific rules like an invalid SKU.

**Cause:** `terraform-linters/setup-tflint` or the ruleset in `.tflint.hcl` was bumped and added rules.

**Fix now:** Read the rule link in the output and fix the code. If a rule is wrong for this repo, disable it in `.tflint.hcl`:

```hcl
rule "terraform_unused_declarations" { enabled = false }
```

**Prevent:** Pin `TFLINT_VERSION` in `ci.yml` and the ruleset `version` in `.tflint.hcl`, and bump them deliberately.

## CI-05 TFLint `--init` fails with GitHub API rate limit (`403 ... rate limit exceeded`)

**Symptom:** The plugin download fails intermittently.

**Cause:** Unauthenticated GitHub API calls from shared runners hit the rate limit.

**Fix now:** Rerun the job. `ci.yml` already passes `GITHUB_TOKEN` to TFLint. Keep that `env:` entry if you edit the job.

**Prevent:** Keep `GITHUB_TOKEN` on the step. In Azure DevOps, add a `GITHUB_TOKEN` pipeline secret.

## CI-06 Checkov starts failing without any Terraform change

**Symptom:** New `FAILED for resource` lines on unchanged code.

**Cause:** The Checkov version changed (the pin in `ci.yml` / `security-scan.yml` was removed or bumped), which added checks.

**Fix now:** Reproduce locally with the same version:

```bash
docker run --rm -v "$PWD:/src" -w /src bridgecrew/checkov:3.2.296 -d terraform --framework terraform --config-file .checkov.yml --compact
```

Fix the resource, or add the check ID to `.checkov.yml` **with a justification comment**.

**Prevent:** Keep Checkov pinned (`checkov==3.2.296`) and bump it in its own PR.

## CI-07 Gitleaks flags a false positive

**Symptom:** `leaks found: 1` for a value that isn't a secret, such as a test fixture or placeholder GUID.

**Cause:** The value matches a generic secret pattern.

**Fix now:** First confirm it really is harmless. If it is, add its fingerprint (printed in the Gitleaks output) to a `.gitleaksignore` file at the repo root:

```
databricks/src/zingyestates/sample_data.py:generic-api-key:42
```

If it **is** real, go to [SEC-01](10-security-and-secrets.md#sec-01-a-secret-was-committed-or-pushed).

**Prevent:** Use obviously fake values in tests and docs (`<placeholder>`, all-zero GUIDs).

## CI-08 Ruff fails after a Ruff upgrade

**Symptom:** New rule codes such as `UP`, `SIM` or `B` reported on untouched files, or `ruff format --check` wants changes.

**Cause:** Dependabot bumped `ruff` in `requirements-dev.txt`. New releases add rules and adjust formatting.

**Fix now:**

```bash
docker compose run --rm platform sh -c "ruff check --fix . && ruff format databricks tests"
```

Review the diff, then commit it on the Dependabot branch or in a follow-up PR.

**Prevent:** Merge Ruff bumps as their own PR. Pin `rev` in `.pre-commit-config.yaml` to the same version.

## CI-09 Spark tests fail or time out in CI only

**Symptom:** `Py4JJavaError`, `UnsupportedClassVersionError`, or a job over 10 minutes. Local Docker runs pass.

**Cause:** A `setup-java` or runner-image change gave a different Java version, or pytest/PySpark bumps changed behaviour.

**Fix now:** Confirm `actions/setup-java` uses `java-version: "17"`. Rerun once to rule out a flaky runner. Diff `requirements-dev.txt` against the last green commit.

**Prevent:** Keep Java 17 pinned. `pyspark`/`delta-spark` are excluded from Dependabot on purpose.

## CI-10 Push rejected: `refusing to allow an OAuth App to create or update workflow`

**Symptom:** `! [remote rejected] ... refusing to allow an OAuth App to create or update workflow .github/workflows/ci.yml without workflow scope`.

**Cause:** Your `gh` or Git credential lacks the `workflow` scope, which is required to push changes under `.github/workflows/`.

**Fix now:**

```bash
gh auth refresh -h github.com -s workflow
gh auth setup-git
git push
```

**Prevent:** Keep the `workflow` scope on the token you use for this repo.

## CI-11 ADF validate or export fails (`npm run build`)

**Symptom:** `Validation failed`, `reference is empty`, `ENOENT scandir ... adf\pipeline`, or `unsupported node version`.

**Cause:**
- `reference is empty`: a JSON file references something missing, such as the managed VNet `default` or a dataset.
- `ENOENT` with a `C:\c\...` path: Git Bash path mangling. Use `$(pwd -W)`.
- A Node version the utility doesn't support.

**Fix now:**

```bash
cd adf && npm ci && npm run build -- validate "$(pwd -W 2>/dev/null || pwd)" "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zingyestates-dev-data/providers/Microsoft.DataFactory/factories/adf-zingy-dev-ze01"
```

Check that every `referenceName` has a matching file under `adf/`.

**Prevent:** Run `make adf-validate` after editing ADF JSON. Keep `NODE_VERSION` at an LTS that the ADF utility supports (20 or 22).

## CI-12 Dependabot PR fails CI

**Symptom:** A red Dependabot PR.

**Cause:** A breaking change in the bumped dependency (major versions especially: `azurerm`, Actions, `pytest`, `ruff`).

**Fix now:**

```bash
gh pr checkout <number>
# fix, commit, then:
git push
```

Or close it with `@dependabot ignore this major version` if you're not ready.

**Prevent:** Merge minor and patch updates regularly so major upgrades are small. Group related updates in `.github/dependabot.yml` if the PR volume is high.

## CI-13 Dependabot PRs conflict with each other

**Symptom:** After merging one Dependabot PR, others show conflicts in `requirements-dev.txt` or lock files.

**Fix now:** Comment `@dependabot rebase` on each remaining PR.

**Prevent:** Merge them one at a time, or add `groups:` to `.github/dependabot.yml`.

## CI-14 Node.js deprecation warnings on every run

**Symptom:** `Node.js 20 is deprecated. The following actions target Node.js 20 ...`.

**Cause:** Old major versions of actions (for example `actions/setup-python@v5`, `hashicorp/setup-terraform@v3`).

**Fix now:** Merge the Dependabot Actions PRs, or bump the `uses:` versions by hand, then run `actionlint`.

**Prevent:** The weekly `github-actions` Dependabot ecosystem.

## CI-15 A workflow edit breaks with a YAML or expression error

**Symptom:** `Invalid workflow file`, or the run never starts.

**Fix now:**

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd):/repo" -w /repo rhysd/actionlint:latest
```

In Azure DevOps YAML, never put `${{ }}` inside flow mappings (`{ a: ${{ b }} }`). Use block style instead. This caused a real parse failure here.

**Prevent:** Run actionlint before pushing workflow changes. Consider adding it as a CI job.

## CI-16 CI didn't run on my push

**Symptom:** No CI run appears.

**Cause:** `ci.yml` ignores changes only to `docs/**`, `**.md` and `powerbi/**`, and pushes run only for `main`, `develop` and `feature/**`.

**Fix now:** Use `gh workflow run ci.yml --ref <branch>`, or push to a matching branch name.

**Prevent:** Name branches `feature/<topic>`.

## CI-17 Artifacts are missing from an old run

**Symptom:** `zingyestates-wheel` or `adf-arm-template` can't be downloaded.

**Cause:** Artifact retention has expired (90 days by default).

**Fix now:** Rerun CI on that commit: `gh workflow run ci.yml --ref <sha-or-branch>`. The CD pipeline rebuilds from source anyway.

**Prevent:** Nothing depends on old artifacts. Tag releases if you need to keep builds.

## CI-18 A workflow run is stuck in "Queued"

**Cause:** GitHub Actions incident, concurrency group queuing (`ci-<ref>` / `cd-<branch>`), or runner capacity.

**Fix now:** Check https://www.githubstatus.com. Cancel stale runs with `gh run cancel <id>`.

**Prevent:** CI concurrency cancels superseded runs. CD never cancels, because a half-cancelled deployment is worse than a queued one.
