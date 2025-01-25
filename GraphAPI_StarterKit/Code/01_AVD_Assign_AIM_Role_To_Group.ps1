#region Get Credentials from Azure Key Vault
Connect-AzAccount -Tenant '<tenantid>' | Out-Null
# Get Tenant information
$tenantId = Get-AzKeyVaultSecret -VaultName 'kv-demo-expertslive' -Name 'tenant-id' -AsPlainText
$subscriptionId = Get-AzKeyVaultSecret -VaultName 'kv-demo-expertslive' -Name 'subscription-id' -AsPlainText

# Get Service Principal information
$clientId = Get-AzKeyVaultSecret -VaultName 'kv-demo-expertslive' -Name 'spn-automation-id' -AsPlainText
$clientSecret = Get-AzKeyVaultSecret -VaultName 'kv-demo-expertslive' -Name 'spn-automation-secret' -AsPlainText
#endregion

#region Step 00 - Connect to Azure Resource Manager API, using REST API (retrieve bearer token)
# URL for the REST API call
$restUri = "https://login.microsoftonline.com/$tenantId/oauth2/token"
# Method for the REST API call
$restMethod = "POST"
# Body for the REST API call
$restBody = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    resource      = "https://management.azure.com/"
}
# Parameters for the REST API call
$restParams = @{
    Uri         = $restUri
    Method      = $restMethod
    Body        = $restBody
    ContentType = "application/x-www-form-urlencoded"
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Store the access token for the Azure Resource Manager API in a variable
$azureBearerToken = $restResponse.access_token
#endregion

#region Step 00 - Connect to Microsoft Graph API (retrieve bearer token)
# URL for the REST API call
$restUri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
# Method for the REST API call
$restMethod = "POST"
# Body for the REST API call
$restBody = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    scope      = "https://graph.microsoft.com/.default"
}
# Parameters for the REST API call
$restParams = @{
    Uri         = $restUri
    Method      = $restMethod
    Body        = $restBody
    ContentType = "application/x-www-form-urlencoded"
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Store the access token for the Microsoft Graph API in a variable
$graphBearerToken = $restResponse.access_token
#endregion

#region Step 01 - Get the Entra Group ID
# URL for the REST API call
$restUri = "https://graph.microsoft.com/v1.0/groups"
$restUri += "?`$filter=startswith(displayName, 'grp-sec-AVD')"   # filter
$restUri += "&`$top=1&`$select=id, displayName,description"      # select
# Method for the REST API call
$restMethod = "GET"
# NO Body for a REST API call with Method GET
$restHeaders = @{
    "Authorization"="Bearer $graphBearerToken"; 
    "Content-Type" = "application/json"
}
# Parameters for the REST API call
$restParams = @{
    Uri         = $restUri
    Method      = $restMethod
    Headers     = $restHeaders
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Output the REST API call results
$groupId = $restResponse.value.id
Write-Host "Step 01 - groupId: " -NoNewline -ForegroundColor Yellow
Write-Host "$($groupId) (GRAPH API)" -ForegroundColor Cyan
#endregion

#region Step 02 - Get roleDefinition ID
# URL for the REST API call
$restUri = "https://management.azure.com/subscriptions/$subscriptionId"
$restUri +="/providers/Microsoft.Authorization/roleDefinitions"
$restUri += "?api-version=2022-04-01"
$restUri += "&`$filter=roleName eq  'Virtual Machine User Login'"
# Method for the REST API call
$restMethod = "GET"
# NO Body for a REST API call with Method GET
$restHeaders = @{
    "Authorization"="Bearer $azureBearerToken"; 
    "Content-Type" = "application/json"
}
# Parameters for the REST API call
$restParams = @{
    Uri         = $restUri
    Method      = $restMethod
    Headers     = $restHeaders
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Output the REST API call results
$roleDefinitionId = $restResponse.value.name
Write-Host "Step 02 - roleDefinitionId: " -NoNewline -ForegroundColor Yellow
Write-Host "$($roleDefinitionId) (ARM API)" -ForegroundColor Cyan
#endregion

#region Step 03 - Get Session Host Name
$resourceGroupName = "rg-avd-resources"
$hostpoolName = "hp-avd-demo"
# URL for the REST API call
$restUri = "https://management.azure.com/subscriptions/$subscriptionId"
$restUri += "/resourceGroups/$resourceGroupName"
$restUri += "/providers/Microsoft.DesktopVirtualization/hostPools/$hostpoolName"
$restUri += "/sessionHosts?api-version=2019-12-10-preview"
$restUri += "&`$select=name, id,type"
# Method for the REST API call
$restMethod = "GET"
# NO Body for a REST API call with Method GET
$restHeaders = @{
    "Authorization"="Bearer $azureBearerToken"; 
    "Content-Type" = "application/json"
}
# Parameters for the REST API call
$restParams = @{
    Uri         = $restUri
    Method      = $restMethod
    Headers     = $restHeaders
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Output the REST API call results
$sessionhostName = $restResponse.value.name.Split('/')[-1]
Write-Host "Step 03 - sessionhostName: " -NoNewline -ForegroundColor Yellow
Write-Host "$($sessionhostName) (ARM API)" -ForegroundColor Cyan
#endregion

#region Step 04 - Assign Role to Entra Group
$resourceGroupName = "rg-avd-resources"
# Create a unique GUID for the roleAssignment ID
$roleassignmentId = [guid]::NewGuid()
# URL for the REST API call
$restUri = "https://management.azure.com/subscriptions/$subscriptionId"
$restUri += "/resourceGroups/$resourceGroupName"
$restUri += "/providers/Microsoft.Compute/virtualMachines/$sessionhostName"
$restUri += "/providers/Microsoft.Authorization/roleAssignments/$($roleassignmentId)"
$restUri += "?api-version=2022-04-01"
# Method for the REST API call
$restMethod = "PUT"
# Body for a REST API call with Method PUT
$restBody = @{
    properties = @{
        principalId = $groupId
        roleDefinitionId = "/providers/Microsoft.Authorization/roleDefinitions/$($roleDefinitionId)"
        principelType = "Group"
    }
}
# Headers for the REST API call
$restHeaders = @{
    "Authorization"="Bearer $azureBearerToken"; 
    "Content-Type" = "application/json"
}
# Parameters for the REST API call
$restParams = @{
    Uri         = $restUri
    Method      = $restMethod
    Body        = ConvertTo-Json -InputObject $restBody -Depth 10 -Compress
    Headers     = $restHeaders
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Output the REST API call results
$roleAssignmentName = $restResponse.name
Write-Host "Step 04 - roleAssignmentName: " -NoNewline -ForegroundColor Yellow
Write-Host "$($roleAssignmentName) (ARM API)" -ForegroundColor Cyan
#endregion

