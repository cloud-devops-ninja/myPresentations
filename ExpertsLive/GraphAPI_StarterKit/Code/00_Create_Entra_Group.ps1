#region logon to azure (interactive)
az login --output none

# set subscription
az account set --subscription "Visual Studio Enterprise" --output none
#endregion

# deploy the bicep template with azure CLI
# https://learn.microsoft.com/en-us/cli/azure/deployment/group?view=azure-cli-latest
$results = az deployment group create --resource-group "rg-graph-demo" `
  --template-file "00_Create_Entra_Group.bicep" `
  --parameters "00_Create_Entra_Group.bicepparam" `
  --output json

#show deployment results
$results | ConvertFrom-Json | Select-Object resourceGroup, name, type, location, tags -ExpandProperty properties | Select-Object -Property provisioningState, resourceGroup, name, type, location, tags | format-list


