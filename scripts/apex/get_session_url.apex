/**
 * get_session_url.apex
 *
 * Generates a front-door session URL for the current user and surfaces it
 * via an intentional assertion failure — the error message prints the full
 * URL unredacted in the Developer Console / CLI output.
 *
 * Usage: Execute via Developer Console > Execute Anonymous, or:
 *   sf apex run --file scripts/apex/get_session_url.apex
 */

String sid         = UserInfo.getSessionId();
String instanceUrl = URL.getOrgDomainUrl().toExternalForm();
String fullUrl     = instanceUrl + '/secur/frontdoor.jsp?sid=' + sid;

// Intentional failure — error message surfaces the full URL unredacted.
System.assert(false, fullUrl);
