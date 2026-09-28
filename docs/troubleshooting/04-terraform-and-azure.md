# Terraform and Azure infrastructure (`TF-*`)

Run commands against an environment after `az login` and `az account set --subscription <env-subscription>`:

```bash
terraform -chdir=terraform init -reconfigure -backend-config=environments/<env>/backend.hcl
```

## TF-01 `Error acquiring the state lock`

**Symptom:** `state blob is already locked`, with a lock ID, who holds it, and when it was taken.

**Cause:** Another run is in progress, or a cancelled or crashed run left the blob lease behind.

**Fix now:** First make sure no pipeline is running (`gh run list`, Azure DevOps runs). Then:

```bash
terraform -chdir=terraform force-unlock <LOCK_ID>
# If that fails, break the blob lease directly:
az storage blob lease break --account-name stzingytfstate --container-name tfstate-<env> --blob-name platform.tfstate --auth-mode login
```

**Prevent:** Don't cancel applies halfway through. The pipelines use `-lock-timeout=5m` and CD concurrency groups.

## TF-02 Drift: someone changed resources in the portal

**Symptom:** A plan shows unexpected updates or replacements, or an apply reverts someone's fix.

**Fix now:**

```bash
terraform -chdir=terraform plan -var-file=environments/<env>/terraform.tfvars -refresh-only
```

Decide which side is right. Either codify the manual change in Terraform, or let the apply revert it.

**Prevent:** Give people Reader roles in higher environments and change things only through PRs. A scheduled weekly `plan -detailed-exitcode` job can alert on drift.

## TF-03 `StorageAccountAlreadyTaken` or name not available

**Symptom:** `The storage account named stzingyqaze01dl is already taken`.

**Cause:** Storage, Key Vault, Data Factory and Synapse names are **globally** unique. Another tenant already holds the name.

**Fix now:**

```bash
az storage account check-name --name stzingyqaze01dl
```

Change `name_suffix` in `terraform/environments/<env>/terraform.tfvars` (2-4 lowercase alphanumerics) and redeploy. Also update `ADF_BUILD_FACTORY_ID` / `adfBuildFactoryId` and `adf/factory/*.json` if you change the dev suffix.

**Prevent:** Choose a distinctive suffix per organisation.

## TF-04 Key Vault name exists in deleted state

**Symptom:** `VaultAlreadyExists` or `A vault with the same name already exists in deleted state`.

**Cause:** The vault was deleted but is kept for 90 days (soft delete). **Purge protection** is on, so it can't be purged early.

**Fix now:** Recover it and let Terraform manage it again:

```bash
az keyvault list-deleted --query "[].name"
az keyvault recover --name kv-zingy-<env>-<suffix>
terraform -chdir=terraform import 'module.key_vault.azurerm_key_vault.this' \
  /subscriptions/<sub>/resourceGroups/rg-zingyestates-<env>-data/providers/Microsoft.KeyVault/vaults/kv-zingy-<env>-<suffix>
```

Or change `name_suffix`.

**Prevent:** Never delete environment vaults casually. They're protected on purpose.

## TF-05 Resource group can't be deleted (`contains resources`)

**Cause:** The provider feature `prevent_deletion_if_contains_resources = true` is on, and Databricks and Synapse create resources outside Terraform (managed resource groups, private endpoints).

**Fix now:** For a deliberate teardown of a non-prod environment: `terraform destroy`. If leftovers remain, delete them in the portal first, or temporarily set the feature to `false`.

**Prevent:** This is intended protection.

## TF-06 `RoleAssignmentExists`

**Symptom:** `The role assignment already exists`.

**Cause:** Someone created the same assignment manually, or a previous apply wrote it but lost the state update.

**Fix now:** Find the existing assignment ID and import it:

```bash
az role assignment list --assignee <principal-id> --scope <scope> --query "[].id" -o tsv
terraform -chdir=terraform import 'azurerm_role_assignment.adf_lake' <assignment-id>
```

**Prevent:** Manage all RBAC for platform identities in Terraform only.

## TF-07 Regional capacity or quota errors when creating resources

**Symptom:** `QuotaExceeded`, `SkuNotAvailable`, or `The requested VM size ... is not available in location`.

**Fix now:**

```bash
az vm list-usage --location eastus2 -o table | grep -i -E "Total Regional|DSv5|DDSv5"
az vm list-skus --location eastus2 --size Standard_D4ds_v5 -o table
```

Request a quota increase (Portal → Quotas), or change `node_type` in `databricks/databricks.yml` or the region in tfvars.

**Prevent:** Before scaling out, check headroom against `max_workers` × vCPUs per node.

## TF-08 Databricks workspace creation fails on VNet injection

**Symptom:** Errors mentioning subnet delegation, NSG association, `SubnetsNotDelegated`, or a network intent policy.

**Cause:** The subnets aren't delegated to `Microsoft.Databricks/workspaces`, the NSG association is missing, or someone added custom NSG rules that conflict with the rules Databricks manages.

**Fix now:** Check `terraform/modules/networking/main.tf`: both `snet-databricks-*` subnets must have the delegation and the NSG association. Remove manual NSG rules from `nsg-zingy-<env>-databricks`.

**Prevent:** Don't add rules to the Databricks NSG. Databricks manages them.

## TF-09 Subnet or address-space conflict

**Symptom:** `NetcfgSubnetRangesOverlap`, or peering fails because ranges overlap with a corporate network.

**Fix now:** Change `vnet_address_space` in tfvars to a free /22. Note that changing a VNet's address space replaces the subnets, Databricks and private endpoints, so plan carefully in higher environments.

**Prevent:** Reserve the ranges with the network team (`docs/environments.md` lists them).

## TF-10 Private endpoint DNS doesn't resolve (resources reached on public IPs or time out)

**Symptom:** `nslookup stzingy<env><sfx>dl.dfs.core.windows.net` returns a public IP from inside the VNet, or connections time out.

**Cause:** The private DNS zone isn't linked to the VNet, the DNS zone group is missing on the endpoint, or clients use custom DNS without forwarding.

**Fix now:**

```bash
az network private-dns link vnet list -g rg-zingyestates-<env>-data -z privatelink.dfs.core.windows.net -o table
az network private-endpoint dns-zone-group list -g rg-zingyestates-<env>-data --endpoint-name pe-<name> -o table
```

For custom DNS servers, add conditional forwarders for the `privatelink.*` zones to 168.63.129.16.

**Prevent:** Keep DNS zones and links in the networking module.

## TF-11 Provider major upgrade breaks validate or plan

**Symptom:** After a Dependabot bump (for example azurerm 4 → 5): `Unsupported argument` or `Missing required argument`.

**Fix now:** Read the provider upgrade guide (`https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/`). Fix each reported resource, then run `make tf-validate`. Example from the azurerm 5 upgrade: `azurerm_private_dns_zone_virtual_network_link` now uses `private_dns_zone_id`.
Always **plan against dev before merging**, and look for `must be replaced` on stateful resources (storage, Key Vault, Synapse).

**Prevent:** Upgrade one major version at a time, in its own PR.

## TF-12 A plan wants to replace a stateful resource

**Symptom:** `# module.storage.azurerm_storage_account.this must be replaced`.

**Cause:** A change to an immutable argument, such as the name, `is_hns_enabled`, `account_kind`, location, or some replication changes.

**Fix now:** **Stop, and don't approve.** Revert the change, or plan a migration (copy the data, or `terraform state mv` if it's only a refactor). For refactors use `moved` blocks:

```hcl
moved {
  from = module.storage.azurerm_storage_container.filesystems["gold"]
  to   = module.storage.azurerm_storage_container.zones["gold"]
}
```

**Prevent:** Reviewers check the plan summary for `must be replaced` before approving. Consider `lifecycle { prevent_destroy = true }` on the lake and Key Vault in prod.

## TF-13 Terraform version too old for a new provider or backend feature

**Symptom:** `Unsupported Terraform Core version` or unknown backend arguments.

**Fix now:** Bump `TERRAFORM_VERSION` in `.github/workflows/*.yml`, `terraformVersion` in `pipelines/variables/common.yml`, and the dev container feature together.

**Prevent:** Review Terraform versions quarterly ([AGE-05](12-aging-and-maintenance.md#age-05-terraform-cli-and-provider-versions-fall-behind)).

## TF-14 Managed private endpoints stuck `Pending`

**Symptom:** ADF managed private endpoints (`mpe-lake-dfs`, `mpe-key-vault`) show Pending, and ADF copies fail.

**Cause:** Private-endpoint connections need approval on the target resource.

**Fix now:**

```bash
for id in $(az network private-endpoint-connection list --id <storage-or-kv-resource-id> \
  --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id" -o tsv); do
  az network private-endpoint-connection approve --id "$id" --description "ADF managed VNet"
done
```

**Prevent:** This is a one-time step per environment ([operations.md](../operations.md#first-deployment)). It recurs if the factory or endpoints are recreated.

## TF-15 `Resource already exists - to be managed via Terraform this resource needs to be imported`

**Cause:** The resource was created outside Terraform, or state was lost or rolled back.

**Fix now:** `terraform import '<address>' <azure-resource-id>`, then run a plan to confirm there are no changes. If state was lost, restore a previous blob version:

```bash
az storage blob list --account-name stzingytfstate -c tfstate-<env> --include v --auth-mode login -o table
```

**Prevent:** The state account has versioning, soft delete and a delete lock (`scripts/bootstrap-tfstate.sh`).

## TF-16 Azure Policy denies a deployment

**Symptom:** `RequestDisallowedByPolicy` with a policy assignment name.

**Cause:** An organisation policy, for example allowed locations, required tags, denying public network access, or requiring CMK.

**Fix now:** Read the policy definition in the error. Adjust tfvars or tags (add them via `var.tags`), or request an exemption.

**Prevent:** Before onboarding a subscription, compare the policies assigned to it against `.checkov.yml` exceptions.
