#region Get Credentials from Azure Key Vault
Connect-AzAccount -Tenant '<tenantid>' | Out-Null
# Get Tenant information
$tenantId = Get-AzKeyVaultSecret -VaultName 'kv-demo-expertslive' -Name 'tenant-id' -AsPlainText

# Get Service Principal information
$clientId = Get-AzKeyVaultSecret -VaultName 'kv-demo-expertslive' -Name 'spn-automation-id' -AsPlainText
$clientSecret = Get-AzKeyVaultSecret -VaultName 'kv-demo-expertslive' -Name 'spn-automation-secret' -AsPlainText
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
$restUri += "?`$filter=startswith(displayName, 'grp-sec-W365')"   # filter
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
Write-Host "$($groupId)" -ForegroundColor Cyan
#endregion

#region Step 02 - Get the Entra User ID
# URL for the REST API call
$restUri = "https://graph.microsoft.com/v1.0/users"
$restUri += "?`$filter=startswith(displayName, 'test01')"   # filter
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
$userId = $restResponse.value.id
Write-Host "Step 02 - User Id: " -NoNewline -ForegroundColor Yellow
Write-Host "$($userId)" -ForegroundColor Cyan
#endregion

#region Step 03 - Add Member to Group
# URL for the REST API call
$restUri = "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref"
# Method for the REST API call
$restMethod = "POST"
# Body for a REST API call with Method PUT
$restBody = @{
    "@odata.id"            = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
}
# Headers for the REST API call
$restHeaders = @{
    "Authorization" = "Bearer $graphBearerToken"; 
    "Content-Type"  = "application/json"
}
# Parameters for the REST API call
$restParams = @{
    Uri     = $restUri
    Method  = $restMethod
    Body    = ConvertTo-Json -InputObject $restBody -Depth 10 -Compress
    Headers = $restHeaders
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Output the REST API call results
Write-Host "Step 03 - User added to Group" -ForegroundColor Yellow
#endregion

