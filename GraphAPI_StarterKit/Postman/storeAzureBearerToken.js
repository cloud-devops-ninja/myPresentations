// post-request script to store the Azure BearerToken into a global variable
pm.test(pm.info.requestName, () => {
    pm.response.to.not.be.error;
    pm.response.to.not.have.jsonBody('error');
});
pm.globals.set("azureBearerToken", pm.response.json().access_token);
// output to console
console.log('Step 00 - ARM BearerToken: '+ pm.response.json().access_token.substring(0,25) + '...');