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
    scope         = "https://graph.microsoft.com/.default"
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
Write-Host "Step 00 - Graph bearer token: " -NoNewline -ForegroundColor Yellow
Write-Host "$($graphBearerToken.Substring(0,25))..." -ForegroundColor Cyan
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
    "Authorization" = "Bearer $graphBearerToken"; 
    "Content-Type"  = "application/json"
}
# Parameters for the REST API call
$restParams = @{
    Uri     = $restUri
    Method  = $restMethod
    Headers = $restHeaders
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Output the REST API call results
$groupId = $restResponse.value.id
Write-Host "Step 01 - groupId: " -NoNewline -ForegroundColor Yellow
Write-Host "$($groupId)" -ForegroundColor Cyan
#endregion

#region Step 02 - Get the Gallery Image ID
# URL for the REST API call
$restUri = "https://graph.microsoft.com/v1.0/deviceManagement/virtualEndpoint/galleryImages"
$restUri += "?`$filter=startswith(skuName, 'win11-23h2-ent-cpc-m365')"   # filter
# Method for the REST API call
$restMethod = "GET"
# NO Body for a REST API call with Method GET
$restHeaders = @{
    "Authorization" = "Bearer $graphBearerToken"; 
    "Content-Type"  = "application/json"
}
# Parameters for the REST API call
$restParams = @{
    Uri     = $restUri
    Method  = $restMethod
    Headers = $restHeaders
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Output the REST API call results
$galleryImageId = $restResponse.value.id
Write-Host "Step 02 - Gallery Image Id: " -NoNewline -ForegroundColor Yellow
Write-Host "$($galleryImageId)" -ForegroundColor Cyan
#endregion

#region Step 03 - Get the CloudPC Serviceplan ID
# URL for the REST API call
$restUri = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/frontLineServicePlans"
# Method for the REST API call
$restMethod = "GET"
# NO Body for a REST API call with Method GET
$restHeaders = @{
    "Authorization" = "Bearer $graphBearerToken"; 
    "Content-Type"  = "application/json"
}
# Parameters for the REST API call
$restParams = @{
    Uri     = $restUri
    Method  = $restMethod
    Headers = $restHeaders
}
# Make the REST API call to retrieve the token response and store it in a variable
$restResponse = Invoke-RestMethod @restParams
# Output the REST API call results
$serviceplanId = $restResponse.value.id
Write-Host "Step 03 - Serviceplan Id: " -NoNewline -ForegroundColor Yellow
Write-Host "$($serviceplanId)" -ForegroundColor Cyan
#endregion

#region Step 04 - Create CloudPC Provisioning Policy
# URL for the REST API call
$restUri = "https://graph.microsoft.com/v1.0/deviceManagement/virtualEndpoint/provisioningPolicies"
# Method for the REST API call
$restMethod = "POST"
# Body for a REST API call with Method PUT
$restBody = @{
    "@odata.type"            = "#microsoft.graph.cloudPcProvisioningPolicy"
    description              = "Windows 365 CloudPC Frontline Provisioning Policy"
    displayName              = "CPC-W365-Frontline-Provisioning"
    domainJoinConfigurations = @(
        @{
            domainJoinType         = "azureADJoin"
            regionName             = "automatic"
            onPremisesConnectionId = $null
            regionGroup            = "europeUnion"
        }
    )
    enableSingleSignOn       = $true
    imageDisplayName         = "win11-23h2-ent-cpc-m365"
    imageId                  = "$($galleryImageId)"
    imageType                = "gallery"
    cloudPcNamingTemplate    = "CPC-%USERNAME:5%-%RAND:5%"
    windowsSetting           = @{
        locale = "en-US"
    }
    microsoftManagedDesktop  = @{
        managedType = "notManaged"
        profile     = ""
    }
    provisioningType         = "shared"
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
$provisioningPolicyId = $restResponse.id
Write-Host "Step 04 - Provisioning Policy Id: " -NoNewline -ForegroundColor Yellow
Write-Host "$($provisioningPolicyId)" -ForegroundColor Cyan
#endregion

#region Step 05 - Assign Entra Group and Serviceplan to CloudPC Provisioning Policy
# URL for the REST API call
$restUri = "https://graph.microsoft.com/v1.0/deviceManagement/virtualEndpoint/provisioningPolicies"
$restUri += "/$($provisioningPolicyId)/assign"
# Method for the REST API call
$restMethod = "POST"
# Body for a REST API call with Method PUT
$restBody = @{
    assignments = @(
        @{
            target = @{
                "@odata.type" = "microsoft.graph.cloudPcManagementGroupAssignmentTarget"
                groupId = "$($groupId)"
                servicePlanId = "$($serviceplanId)"
            }
        }
    )
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
Write-Host "Step 05 - Group and Serviceplan assigned to policy"-ForegroundColor Yellow
#endregion
