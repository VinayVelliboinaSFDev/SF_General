public class XAI_Integration {
	@AuraEnabled
    public static String getXaiResponse(String userInput) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        // Use a Named Credential — never hardcode API keys in source code.
        // Setup: Named Credential "XAI_NC" with endpoint https://api.x.ai
        // and an External Credential storing the Bearer token.
        request.setEndpoint('callout:XAI_NC/v1/chat/completions');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');

        // Construct JSON body
        Map<String, Object> payload = new Map<String, Object>{
            'model' => 'grok-3-latest',
            'stream' => false,
            'temperature' => 0,
            'messages' => new List<Map<String, String>>{
                new Map<String, String>{'role' => 'system', 'content' => 'You are a test assistant.'},
                new Map<String, String>{'role' => 'user', 'content' => userInput}
            }
        };

        String requestBody = JSON.serialize(payload);
        request.setBody(requestBody);

        try {
            HttpResponse response = http.send(request);
            return response.getBody(); // You may parse the JSON here if needed
        } catch (Exception ex) {
            return 'Error: ' + ex.getMessage();
        }
    }
}