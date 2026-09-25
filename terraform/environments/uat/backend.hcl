# Remote state for the uat platform. Created by scripts/bootstrap-tfstate.sh.
resource_group_name  = "rg-zingyestates-tfstate"
storage_account_name = "stzingytfstate"
container_name       = "tfstate-uat"
key                  = "platform.tfstate"
use_azuread_auth     = true
