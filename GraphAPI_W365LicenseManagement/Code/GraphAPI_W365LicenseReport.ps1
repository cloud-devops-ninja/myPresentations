<#
.SYNOPSIS
    Generates comprehensive Windows 365 Cloud PC license and usage reports using Microsoft Graph API.

.DESCRIPTION
    This script connects to Microsoft Graph API to retrieve detailed information about Windows 365 Cloud PCs,
    service plans, provisioning policies, license groups, and user activity. It generates both raw and enriched
    reports that help administrators manage Windows 365 licensing and identify inactive Cloud PCs.

    The script performs the following operations:
    - Authenticates with Microsoft Graph API using application credentials
    - Retrieves Windows 365 service plans and provisioning policies
    - Collects license group information and Cloud PC details
    - Generates aggregated remote connection reports with enhanced data
    - Identifies inactive Cloud PCs based on configurable criteria (default: 60 days)
    - Exports data to both JSON and CSV formats for analysis

    Key Features:
    - Filters out production (PRD) Cloud PCs from license checks
    - Identifies never-signed-in Cloud PCs older than specified days
    - Tracks last active time for signed-in Cloud PCs
    - Enriches data with service plan details, provisioning policies, and user information
    - Handles Graph API pagination for large datasets
    - Converts tenant-specific UPNs to contact email addresses

.PARAMETER TenantId
    The Azure Active Directory tenant ID where Windows 365 Cloud PCs are deployed.

.PARAMETER ClientId
    The application (client) ID of the Azure AD app registration with required Graph API permissions.

.PARAMETER ClientSecret
    The client secret for the Azure AD app registration used for authentication.

.PARAMETER FileOutputPath
    The directory path where output files will be saved. Defaults to "C:\Temp".

.EXAMPLE
    .\GraphAPI_W365LicenseReport.ps1 -TenantId "12345678-1234-1234-1234-123456789012" -ClientId "87654321-4321-4321-4321-210987654321" -ClientSecret "your-client-secret"
    
    Generates Windows 365 reports using the specified tenant and application credentials, saving files to the default C:\Temp directory.

.EXAMPLE
    .\GraphAPI_W365LicenseReport.ps1 -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret -FileOutputPath "D:\Reports"
    
    Generates reports and saves output files to the specified D:\Reports directory.

.NOTES
    File Name      : GraphAPI_W365LicenseReport.ps1
    Author         : Esther Barthel, MSc
    Version        : 1.0
    Prerequisite   : Azure AD app registration with Microsoft Graph permissions:
                     - CloudPC.Read.All
                     - Group.Read.All
                     - User.Read.All
                     - DeviceManagementManagedDevices.Read.All
                     - Reports.Read.All
    
    Output Files:
    - Windows365RawAggregatedRemoteConnections_[date].json/.csv
    - Windows365EnrichedAggregatedRemoteConnections_[date].json/.csv
    - W365FilteredCloudPCNames_[date].json
    - W365CloudPCsInactiveLast60Days_[date].json/.csv

.LINK
    https://docs.microsoft.com/en-us/graph/api/resources/cloudpc
    https://docs.microsoft.com/en-us/windows-365/
#>

[cmdletbinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientId,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientSecret,
    [Parameter(Mandatory = $false)]
    [string]$FileOutputPath = "C:\Temp"
)

####################################
# Script Functions                 #
####################################
#region W365 license management functions

# Graph Authentication functions
function Get-GraphAccessToken {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppSecret
    )

    # Create URI for Graph call to authenticate against Graph and retrieve an access_token
    $uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    # Set Method to POST
    $method = "POST"

    # Create Request Header
    $authHeader = @{
        'Content-Type' = 'application/x-www-form-urlencoded'
    }

    # Create Request Body
    $body = @{
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $AppId
        client_secret = $AppSecret
        grant_type    = "client_credentials"
    }

    # Make the webrequest to retrieve the access token
    $webRequestParams = @{
        Uri     = $uri
        Headers = $authHeader
        Method  = $method
        Body    = $body
    }
    $webrequestResult = Invoke-WebRequest @webRequestParams
    $graphContext = ConvertFrom-Json -InputObject $($webrequestResult.Content)

    # Return Graph conbtext
    return $graphContext
}

# Search Table functions
function Get-W365ServicePlans {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken
    )

    #region Create URI for Graph call to collect all available service plans for Windows365
    $uri = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/servicePlans"
    $uri += "?`$filter=supportedSolution eq 'windows365' &`$count=true"

    # Set method to GET
    $method = "GET"

    # Create Header
    $authHeader = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
        #'ConsistencyLevel' = 'eventual'
    }

    # Create webrequest parameters in hashtable
    $webRequestParams = @{
        Uri     = $uri
        Headers = $authHeader
        Method  = $method
        Verbose = $true
    }

    # Make the webrequest to retrieve the Windows365 Service Plans
    $webrequestResult = Invoke-WebRequest @webRequestParams

    # Process the result of the webrequest
    $w365ServicePlans = ConvertFrom-Json -InputObject $($webrequestResult.Content)
    Write-Verbose "Windows365 Service Plans: $($($w365ServicePlans.value).Count)"

    # Create a search table with the most important information of the Windows365 Service Plans
    $w365ServicePlanSearchTable = $w365ServicePlans.value

    # Return Service Plans
    return $w365ServicePlanSearchTable
}

function Get-W365ProvisioningPolicyGroups {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProvisioningPolicyGroupDisplayName
    )

    # Create URI for Graph call to collect Entra Groups used for provisioning policies for Windows365
    $uri = "https://graph.microsoft.com/beta/groups"
    $uri += "?`$filter=startsWith(displayName,'$($ProvisioningPolicyGroupDisplayName)') &`$count=true"

    # Set method to GET
    $method = "GET"

    # Create Header
    $authHeader = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
        #'ConsistencyLevel' = 'eventual'
    }

    # Create webrequest parameters in hashtable
    $webRequestParams = @{
        Uri     = $uri
        Headers = $authHeader
        Method  = $method
        Verbose = $true
    }

    # Make the web request to retrieve the Windows365 Provisioning Policy Groups
    $webrequestResult = Invoke-WebRequest @webRequestParams

    # Process the result of the web request
    $w365ProvisioningPolicyGroups = ConvertFrom-Json -InputObject $($webrequestResult.Content)
    Write-Verbose "Windows365 Provisioning Policy Groups: $($($w365ProvisioningPolicyGroups.value).Count)"

    # Create a search table with the most important information of the Windows365 Provisioning Policy Groups
    $w365ProvisioningPolicyGroupsSearchTable = $w365ProvisioningPolicyGroups.value

    # Return Provisioning Policy Groups
    return $w365ProvisioningPolicyGroupsSearchTable
}

function Get-W365LicenseGroups {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LicenseGroupDisplayName
    )

    # Create URI for Graph call to collect Entra Groups used for (Enterprise) licensing for Windows365
    $uri = "https://graph.microsoft.com/beta/groups"
    $uri += "?`$filter=startsWith(displayName,'$($LicenseGroupDisplayName)') &`$count=true"

    # Set method to GET
    $method = "GET"

    # Create Header
    $authHeader = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
        #'ConsistencyLevel' = 'eventual'
    }

    # Create webrequest parameters in hashtable
    $webRequestParams = @{
        Uri     = $uri
        Headers = $authHeader
        Method  = $method
        Verbose = $true
    }

    # Make the webrequest to retrieve the Windows365 License Groups
    $webrequestResult = Invoke-WebRequest @webRequestParams

    # Process the result of the webrequest
    $w365LicenseGroups = ConvertFrom-Json -InputObject $($webrequestResult.Content)
    Write-Verbose "Windows365 License Groups: $($($w365LicenseGroups.value).Count)"

    # Create a search table with the most important information of the Windows365 License Groups
    $w365LicenseGroupsSearchTable = $w365LicenseGroups.value

    # Return License Groups
    return $w365LicenseGroupsSearchTable
}

function Get-W365ProvisioningPolicies {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,
        [Parameter(Mandatory = $true)]
        [array]$ProvisioningPolicyGroupSearchtable,
        [Parameter(Mandatory = $true)]
        [array]$ServicePlanSearchtable
    )

    #region Create URI for Graph call to collect all provisioning policies for Windows365
    $uri = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/provisioningPolicies"
    $uri += "?`$expand=assignments &`$count=true"

    # Set method to GET
    $method = "GET"
    # Create Header
    $authHeader = @{
        'Authorization'     = "Bearer $AccessToken"
        'Content-Type'      = 'application/json'
        'X-Ms-Command-Name' = 'fetchPolicyList'
    }
    # Create webrequest parameters in hashtable
    $webRequestParams = @{
        Uri     = $uri
        Headers = $authHeader
        Method  = $method
        Verbose = $true
    }

    # Make the web request to retrieve the Windows365 Provisioning Policies
    $webrequestResult = Invoke-WebRequest @webRequestParams -Verbose

    # Process the result of the web request
    $w365ProvisioningPolicies = ConvertFrom-Json -InputObject $($webrequestResult.Content)
    Write-Verbose "Windows365 Provisioning Policies: $($($w365ProvisioningPolicies.value).Count)"

    # Create a search table with the most important information of the Windows365 Provisioning Policies
    [array]$w365ProvisioningPoliciesSearchTable = @()
    foreach ($policy in $w365ProvisioningPolicies.value) {
        foreach ($assignment in $policy.assignments) {
            $policyObject = [PSCustomObject]@{
                id                        = $policy.id
                displayName               = $policy.displayName
                imageId                   = $policy.imageId
                imageType                 = $policy.imageType
                imageDisplayName          = $policy.imageDisplayName
                managedBy                 = $policy.managedBy
                provisioningType          = $policy.provisioningType
                assignmentId              = $assignment.id
                assignmentGroupId         = $assignment.target.groupId
                assignmentGroupName       = $ProvisioningPolicyGroupSearchtable.where({ $_.id -eq $assignment.target.groupId }).displayName
                assignmentServicePlanId   = $assignment.target.servicePlanId
                assignmentServicePlanName = $ServicePlanSearchtable.where({ $_.id -eq $assignment.target.servicePlanId }).displayName
            }
            $w365ProvisioningPoliciesSearchTable += $policyObject
        }
    }
    # Return Provisioning Policies
    return $w365ProvisioningPoliciesSearchTable
}

function Get-W365CloudPCs {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken
    )

    # Create URI for Graph call to collect all CloudPCs for Windows365
    $uri = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/cloudPCs"
    $uri += "?`$expand=*&`$count=true"

    # Set method to GET
    $method = "GET"

    # Set Request Headers
    $authHeader = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
    }

    # Create web request parameters
    $webRequestParams = @{
        Uri     = $uri
        Headers = $authHeader
        Method  = $method
    }

    # Make the web request and convert result content to PSObject to retrieve the Windows365 CloudPCs
    $webrequestResult = ConvertFrom-Json -InputObject $($(Invoke-WebRequest @webRequestParams).Content)

    # Create an array to store all CloudPCs
    $allCloudPCs = @()
    $allCloudPCs += $webrequestResult.value

    # Resolve Graph API pagination to retrieve all CloudPCs
    while ($null -ne $webrequestResult.'@odata.nextLink') {
        $uri = $webrequestResult.'@odata.nextLink'
        $webRequestParams = @{
            Uri     = $uri
            Headers = $authHeader
            Method  = $method
        }
        $webrequestResult = ConvertFrom-Json -InputObject $($(Invoke-WebRequest @webRequestParams).Content)
        # Store next page of CloudPCs in the allCloudPCs array
        $allCloudPCs += $($webrequestResult.value)
    }
    # Return the array of all CloudPCs
    return $allCloudPCs
}
# Intune Report functions
function Get-W365AggregatedRemoteConnectionReport {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken
    )

    # Create URI for Graph call to collect the Total Aggregated Remote Connection Report
    $uri = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/reports/getTotalAggregatedRemoteConnectionReports/"
    $uri += "?`$count=true"

    # Set method to POST
    $method = "POST"

    # Create Request Header
    $authHeader = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
    }

    $top = [int]100
    $skip = [int]0

    # Create Request Body
    $bodyObject = @{
        "top"     = $top
        "skip"    = $skip
        "search"  = ""
        "filter"  = ""
        "orderBy" = @("TotalUsageInHour")
    }

    # Create an array to store all AggregatedRemoteConnections
    [array]$rawAggregatedRemoteConnections = @()

    do {
        # Make the web request to retrieve the Total Aggregated Remote Connection Reports
        $webRequestParams = @{
            Uri     = $uri
            Headers = $authHeader
            Method  = $method
            Body    = $(ConvertTo-Json -InputObject $bodyObject -Depth 100)
        }

        # Use Invoke-RestMethod to handle base64-encoded webrequest.content
        $webrequestResults = Invoke-RestMethod @webRequestParams

        # Process the result of the web request
        [int]$totalColumns = ($webrequestResults.Schema | Measure-Object).Count
        foreach ($item in $webrequestResults.Values) {
            $aggregatedRemoteConnection = @{}
            for ($i = 0; $i -lt ($totalColumns - 1); $i++) {
                $aggregatedRemoteConnection.Add($webrequestResults.Schema[$i].Column, $item[$i])
            }
            $rawAggregatedRemoteConnections += $aggregatedRemoteConnection
        }

        # Update skip and check for pagination
        $retrievedRows = ($webrequestResults.Values | Measure-Object).Count
        $skip += $retrievedRows
        $totalRowCount = $webrequestResults.TotalRowCount

        # Update the request body for the next page
        $bodyObject["skip"] = $skip
    } while ($skip -lt $totalRowCount)

    # Return the array of all Aggregated Remote Connections
    return $rawAggregatedRemoteConnections
}

function Get-W365AggregatedRemoteConnectionReportWithEnrichedData {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,
        [Parameter(Mandatory = $true)]
        [array]$ServicePlanSearchtable,
        [Parameter(Mandatory = $true)]
        [array]$LicenseGroupSearchtable,
        [Parameter(Mandatory = $true)]
        [array]$CloudPcSearchtable,
        [Parameter(Mandatory = $true)]
        [array]$ProvisioningPolicySearchtable
    )

    #region Create URI for Graph call to collect the Total Aggregated Remote Connection Reports
    $uri = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/reports/getTotalAggregatedRemoteConnectionReports/"
    $uri += "?`$count=true"

    # Set method to POST
    $method = "POST"

    # Create Request Header
    $authHeader = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
    }

    $top = [int]100
    $skip = [int]0

    # Create Request Body
    $bodyObject = @{
        "top"     = $top
        "skip"    = $skip
        "search"  = ""
        "filter"  = ""
        "orderBy" = @("TotalUsageInHour")
    }

    # Create an array to store all AggregatedRemoteConnections
    [array]$allAggregatedRemoteConnections = @()

    do {
        # Make the web request to retrieve the Total Aggregated Remote Connection Reports
        $webRequestParams = @{
            Uri     = $uri
            Headers = $authHeader
            Method  = $method
            Body    = $(ConvertTo-Json -InputObject $bodyObject -Depth 100)
        }

        # Use Invoke-RestMethod to handle base64-encoded content
        $webrequestResults = Invoke-RestMethod @webRequestParams

        # Process the result of the web request
        [int]$totalColumns = ($webrequestResults.Schema | Measure-Object).Count
        foreach ($item in $webrequestResults.Values) {
            $aggregatedRemoteConnection = @{}
            for ($i = 0; $i -lt ($totalColumns - 1); $i++) {
                $aggregatedRemoteConnection.Add($webrequestResults.Schema[$i].Column, $item[$i])

                # Add ServicePlan details
                if ($webrequestResults.Schema[$i].Column -eq 'ServicePlanId') {
                    $servicePlan = $ServicePlanSearchtable.where({ $_.id -eq $item[$i] })
                    $aggregatedRemoteConnection.Add('ServicePlanName', $servicePlan.displayName)
                    $aggregatedRemoteConnection.Add('ServicePlanType', $servicePlan.type)
                    # Add ServicePlanProvisioningType and ExpectedEnterpriseLicenseGroupName
                    switch ($servicePlan.provisioningType) {
                        'shared' {
                            $ServicePlanProvisioningType = 'Frontline'
                            $EnterpriseLicenseGroupName = ''
                        }
                        'dedicated' {
                            $ServicePlanProvisioningType = 'Enterprise'
                            $EnterpriseLicenseGroupName = "W365-LIC-$($servicePlan.vCpuCount)vCPU-"
                            $EnterpriseLicenseGroupName += "$($servicePlan.ramInGB)GB-"
                            $EnterpriseLicenseGroupName += "$($servicePlan.storageInGB)GB"

                        }
                        default {
                            $ServicePlanProvisioningType = 'Unknown'
                            $EnterpriseLicenseGroupName = ''
                        }
                    }
                    $aggregatedRemoteConnection.Add('ServicePlanProvisioningType', $ServicePlanProvisioningType)
                    $aggregatedRemoteConnection.Add('ExpectedEnterpriseLicenseGroupName', $EnterpriseLicenseGroupName)
                    # search EnterpriseLicenseGroupId in $w365LicenseGroupsSearchTable
                    $licenseGroup = $LicenseGroupSearchtable.where({ $_.displayName -eq $EnterpriseLicenseGroupName })
                    $aggregatedRemoteConnection.Add('ExpectedEnterpriseLicenseGroupId', $($licenseGroup.id))
                }

                # Add CloudPC details
                if ($webrequestResults.Schema[$i].Column -eq 'CloudPcId') {
                    $cloudPC = $CloudPcSearchtable.where({ $_.id -eq $item[$i] })
                    $aggregatedRemoteConnection.Add('CloudPCName', $cloudPC.displayName)
                    $aggregatedRemoteConnection.Add('ProvisioningPolicyId', $cloudPC.provisioningPolicyId)
                    $aggregatedRemoteConnection.Add('ProvisioningPolicyName', $cloudPC.provisioningPolicyName)
                    $aggregatedRemoteConnection.Add('provisioningType', $cloudPC.provisioningType)
                    $aggregatedRemoteConnection.Add('lastModifiedDateTime', $cloudPC.lastModifiedDateTime)
                    $aggregatedRemoteConnection.Add('provisioningStatus', $cloudPC.status)
                    # Add provisioning policy groupname & groupid to dataset
                    $assignmentServicePlanId = $cloudPC.servicePlanId
                    $asignmentProvisioningPolicyId = $cloudPC.provisioningPolicyId
                    $provisioningPolicy = $ProvisioningPolicySearchtable.where({ ($_.id -eq $asignmentProvisioningPolicyId) `
                                -and ( ($_.assignmentServicePlanId -eq $assignmentServicePlanId) -or ($null -eq $_.assignmentServicePlanId) ) })
                    $aggregatedRemoteConnection.Add('provisioningPolicyGroupId', $provisioningPolicy.assignmentGroupId)
                    $aggregatedRemoteConnection.Add('provisioningPolicyGroupName', $provisioningPolicy.assignmentGroupName)
                    $aggregatedRemoteConnection.Add('aadDeviceId', $cloudPC.aadDeviceId)
                    # Convert UPN to contact email address
                    $userPrincipalName = $cloudPC.userPrincipalName
                    if ($userPrincipalName.endsWith('cognitionitdev.onmicrosoft.com')) {
                        $userPrincipalName = $userPrincipalName.Replace('cognitionitdev.onmicrosoft.com', 'cognitionit.com')
                    }
                    if ($userPrincipalName.endsWith('cognitionittst.onmicrosoft.com')) {
                        $userPrincipalName = $userPrincipalName.Replace('cognitionittst.onmicrosoft.com', 'cognitionit.com')
                    }
                    $contactEmail = $userPrincipalName
                    $aggregatedRemoteConnection.Add('contactEmail', $contactEmail)
                }
            }
            $allAggregatedRemoteConnections += $aggregatedRemoteConnection
        }

        # Update skip and check for pagination
        $retrievedRows = ($webrequestResults.Values | Measure-Object).Count
        $skip += $retrievedRows
        $totalRowCount = $webrequestResults.TotalRowCount

        # Update the request body for the next page
        $bodyObject["skip"] = $skip
    } while ($skip -lt $totalRowCount)
    #endregion

    # Return the array of all Aggregated Remote Connections
    return $allAggregatedRemoteConnections
}

# User functions
function Get-W365UserId {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,
        [Parameter(Mandatory = $true)]
        [string]$userPrincipalName
    )

    #region Create URI for Graph call to collect all available service plans for Windows365
    $uri = "https://graph.microsoft.com/v1.0/users/$userPrincipalName"
    $uri += "?`$select=userPrincipalName,id,displayName"

    # Set method to GET
    $method = "GET"

    $authHeader = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
        #'ConsistencyLevel' = 'eventual'
    }

    $webRequestParams = @{
        Uri     = $uri
        Headers = $authHeader
        Method  = $method
        Verbose = $true
    }

    # Make the webrequest to retrieve the Windows365 Service Plans
    $webrequestResult = Invoke-WebRequest @webRequestParams

    # Process the result of the webrequest
    $w365User = ConvertFrom-Json -InputObject $($webrequestResult.Content)
    Write-Verbose "Windows365 User: $(ConvertTo-Json -InputObject $($w365User.id) -Depth 100)"

    return $w365User.id
}
#endregion

###################################
# Script workflow                 #
###################################
# Get the access token
$graphContext = Get-GraphAccessToken -TenantId $tenantId -AppId $ClientId -AppSecret $ClientSecret
# Output the access token
Write-Output "Access Token: $($graphContext.access_token)"

# Build the Searchtables
$w365ServicePlanSearchtable = Get-W365ServicePlans -AccessToken $($graphContext.access_token)
$w365ProvisioningPolicyGroupSearchtable = Get-W365ProvisioningPolicyGroups -AccessToken $($graphContext.access_token) `
    -ProvisioningPolicyGroupDisplayName "grp-prv-W365"
$w365LicenseGroupsSearchtable = Get-W365LicenseGroups -AccessToken $($graphContext.access_token) `
    -LicenseGroupDisplayName "grp-lic-W365"
$w365ProvisioningPoliciesSearchtable = Get-W365ProvisioningPolicies -AccessToken $($graphContext.access_token) `
    -ProvisioningPolicyGroupSearchTable $w365ProvisioningPolicyGroupSearchtable `
    -ServicePlanSearchTable $w365ServicePlanSearchtable
$w365CloudPCs = Get-W365CloudPCs -AccessToken $($graphContext.access_token)

# Output the number of service plans in the search table
Write-Output "Windows365 Service Plan SearchTable: $($w365ServicePlanSearchTable.Count)"
# Output the number of provision policy groups in the search table
Write-Output "Windows365 Provisioning Policy Group SearchTable: $($w365ProvisioningPolicyGroupSearchtable.Count)"
# Output the number of license groups in the search table
Write-Output "Windows365 License Groups SearchTable: $($w365LicenseGroupsSearchTable.Count)"
# Output the number of provisioning policies in the search table
Write-Output "Windows365 Provisioning Policies SearchTable: $($w365ProvisioningPoliciesSearchTable.Count)"
# Output the number of CloudPCs in the search table
Write-Output "Windows365 CloudPCs SearchTable: $($w365CloudPCs.Count)"

#---------------------------------------------------------------------------#
# Retrieve Intune Total Aggregated Remote Connection Report for Windows365  #
#---------------------------------------------------------------------------#
# Get Intune report data for Total Aggregated Remote Connections
$rawAggregatedRemoteConnections = Get-W365AggregatedRemoteConnectionReport -AccessToken $($graphContext.access_token)
$enrichedAggregatedRemoteConnections = Get-W365AggregatedRemoteConnectionReportWithEnrichedData -AccessToken $($graphContext.access_token) `
    -ServicePlanSearchtable $w365ServicePlanSearchtable -LicenseGroupSearchtable $w365LicenseGroupsSearchTable `
    -CloudPcSearchtable $w365CloudPCs -ProvisioningPolicySearchtable $w365ProvisioningPoliciesSearchTable

# Output the number of raw and enriched aggregated remote connections
Write-Output "Retrieved Total Aggregated Remote Connection Report: $($rawAggregatedRemoteConnections.Count)"
Write-Output "Retrieved Enriched Total Aggregated Remote Connection Report: $($enrichedAggregatedRemoteConnections.Count)"

# Export Array of Hashtables to JSON file and CSV
$fileName = "$($FileOutputPath)\Windows365RawAggregatedRemoteConnections_$($fileSuffix)"
ConvertTo-Json -InputObject $rawAggregatedRemoteConnections -Depth 100 | Out-File -FilePath "$($fileName).json" -Force
#Avoid 'Export-Csv: Object reference not set to an instance of an object' error with direct export by loading and converting JSON data and than export to CSV
$jsonRawData = Get-Content -Path "$($fileName).json" -Raw | ConvertFrom-Json
$jsonRawData | Export-Csv -Path "$($fileName).csv" -NoTypeInformation

# Export Array of Hashtables to JSON file and CSV
$fileName = "$($FileOutputPath)\Windows365EnrichedAggregatedRemoteConnections_$($fileSuffix)"
ConvertTo-Json -InputObject $enrichedAggregatedRemoteConnections -Depth 100 | Out-File -FilePath "$($fileName).json" -Force
# Avoid 'Export-Csv: Object reference not set to an instance of an object' error with direct export by loading and converting JSON data and than export to CSV
$jsonEnrichedData = Get-Content -Path "$($fileName).json" -Raw | ConvertFrom-Json
$jsonEnrichedData | Export-Csv -Path "$($fileName).csv" -NoTypeInformation

#------------------------------------------------------------------------#
# FILTERING Enriched Aggregated Remote Connection Report for Windows365  #
#------------------------------------------------------------------------#

Write-Output "-----------"
[int]$daysToAdd = -59
$checkDate = (Get-Date).AddDays($daysToAdd)
$dateFormatString = "MM/dd/yyyy hh:mm:ss tt"
$fileSuffix = Get-Date -Format "yyyyMMdd"
Write-Output "checkDate: $(Get-Date -Date $checkDate -Format $dateFormatString)"
Write-Output "-----------"
#rule 01: No license check for PRD Cloud PCs
$filteredJsonData = $jsonEnrichedData
# Exclude PRD CloudPCs as they will never expire (for now)
$filteredJsonData = $filteredJsonData.Where({ ($_.provisioningPolicyName -notlike 'PRD*') })
# Export filtered json data to JSON file (for logging)
$fileName = "$($FileOutputPath)\W365FilteredCloudPCNames_$($fileSuffix)"
ConvertTo-Json -InputObject $filteredJsonData -Depth 100 | Out-File -FilePath "$($fileName).json" -Force
Write-Output "-----------"
Write-Output "Filtered Total Aggregated Remote Connections (NO PRD): $($filteredJsonData.Count)"
Write-Output "-----------"
#rule 02: For never logged on provisioned CPCs (NeverLoggedIn = true) check CreateDate; if older than $checkDate, email user that license is revoked
#rule 03: For logged on provisioned CPCs (NeverLoggedIn = false) check LastLoggedInDate; if older than $checkDate, email user that license is revoked
# Filter CloudPCs with (NeverLoggedIn eq $true and CreatedDate lt $checkDate) or (NeverLoggedIn eq $false and LastActiveTime le $checkDate)
$totalFilteredJsonData = $filteredJsonData.Where({ (($_.NeverSignedIn -eq $true) -and ($_.CreatedDate -lt $checkDate) -and ($_.provisioningStatus -eq 'provisioned')) `
            -or (($_.NeverSignedIn -eq $false) -and ($_.LastActiveTime -le $checkDate) -and ($_.provisioningStatus -eq 'provisioned')) })
Write-Output "totalFilteredInactiveW365VMs ($([Math]::Abs($daysToAdd)) days ($checkDate)): $($totalFilteredJsonData.Count)"
Write-Output "-----------"

# Loop through the filtered data and add the userId to the hashtable
$enrichedTotalFilteredJsonData = $totalFilteredJsonData
$enrichedTotalFilteredJsonData | ForEach-Object {
    $userPrincipalName = $_.UserPrincipalName
    $userId = Get-W365UserId -AccessToken $($graphContext.access_token) -userPrincipalName $userPrincipalName
    # add the userId to the hashtable
    $_ | Add-Member -MemberType NoteProperty -Name "UserDirectoryObjectId" -Value $userId -Force
}

# Export Array of Hashtables to JSON file
$fileName = "$($FileOutputPath)\W365CloudPCsInactiveLast60Days_$($fileSuffix)"
ConvertTo-Json -InputObject $enrichedTotalFilteredJsonData -Depth 100 | Out-File -FilePath "$($fileName).json" -Force
#Avoid 'Export-Csv: Object reference not set to an instance of an object' error with direct export by loading and converting JSON data and than export to CSV
$finalJsonData = Get-Content -Path "$($fileName).json" -Raw | ConvertFrom-Json
# Final data of CloudPCs that have been inactive for 60 days filtered json data to CSV
$finalJsonData | Export-Csv -Path "$($fileName).csv" -NoTypeInformation -Force