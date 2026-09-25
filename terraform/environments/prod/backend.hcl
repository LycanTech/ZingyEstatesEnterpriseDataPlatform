# Remote state for the prod platform. Created by scripts/bootstrap-tfstate.sh.
resource_group_name  = "rg-zingyestates-tfstate"
storage_account_name = "stzingytfstate"
container_name       = "tfstate-prod"
key                  = "platform.tfstate"
use_azuread_auth     = true
