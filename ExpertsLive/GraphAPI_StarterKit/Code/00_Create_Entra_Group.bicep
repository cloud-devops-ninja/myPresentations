// set scope to resource group
targetScope = 'resourceGroup'

// Directory Object IDs for group membership
@description('Enter the Directory Object IDs for the users to add to the group')
param entraUsersObjectId array = []

// add the Graph provider for Bicep
extension microsoftGraphV1

// create an Entra Group with a single member (using the Graph provider)
resource entraGroup 'Microsoft.Graph/groups@v1.0' = {
  uniqueName: 'GraphAPI_StarterKit_Group'
  displayName: 'GraphAPI_StarterKit_Group'
  mailEnabled: false
  mailNickname: 'GraphAPI_StarterKit_Group'
  securityEnabled: true
  description: 'This group was created using Bicep and the Microsoft Graph API'
  groupTypes: []
  visibility: 'Private'
  members: {
    relationships: [for userId in entraUsersObjectId: 'https://graph.microsoft.com/v1.0/directoryObjects/${userId}']
    relationshipSemantics: 'append'
  }
}

// output the group ID
output entraGroupId string = entraGroup.id
