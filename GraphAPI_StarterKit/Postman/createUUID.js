// pre-request script
// create a unique uuid to use in request: 04. ARM: Create RoleAssignment
var uuid = require('uuid');
var myUUID = uuid.v4();
//console.log(myUUID);
pm.environment.set('roleassignment-id',myUUID);