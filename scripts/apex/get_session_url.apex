/**
 * get_session_url.apex
 *
 * Generates a front-door session URL for the current user and stores it
 * in the Description field of the designated test Account record.
 *
 * Usage: Execute via Developer Console > Execute Anonymous, or:
 *   sf apex run --file scripts/apex/get_session_url.apex
 *
 * NOTE: The Account Id below is a test record used solely to surface the URL.
 */

String sid         = UserInfo.getSessionId();
String instanceUrl = URL.getOrgDomainUrl().toExternalForm();
String fullUrl     = instanceUrl + '/secur/frontdoor.jsp?sid=' + sid;

System.debug('Session URL: ' + fullUrl);

Account acc = new Account(
    Id          = '001g500000BGVGAAA5',
    Description = fullUrl
);
update acc;
