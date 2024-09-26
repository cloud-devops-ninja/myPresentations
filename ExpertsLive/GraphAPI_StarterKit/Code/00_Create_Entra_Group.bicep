// set scope to resource group
targetScope = 'resourceGroup'

// Directory Object IDs for group membership
@description('Enter the Directory Object IDs for the users to add to the group')
param entraUsersObjectId array = []

// add the Graph provider for Bicep
extension microsoftGraph

// create an Entra Group with a single member (using the Graph provider)
resource entraGroup 'Microsoft.Graph/groups@v1.0' = {
  displayName: 'grp-sec-bicepDemo'
  mailEnabled: false
  mailNickname: 'grp-sec-bicepDemo'
  securityEnabled: true
  uniqueName: 'grp-sec-bicepDemo'
  members: entraUsersObjectId
}




