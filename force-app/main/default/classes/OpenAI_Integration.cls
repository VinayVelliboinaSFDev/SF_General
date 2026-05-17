public class OpenAI_Integration {
    @AuraEnabled
    public static string openAIResponse(String userInput ){
        String responseString = '';
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        // Use a Named Credential — never hardcode API keys in source code.
        // Setup: Named Credential "OpenAI_NC" with endpoint https://api.openai.com
        // and an External Credential storing the Bearer token.
        request.setEndpoint('callout:OpenAI_NC/v1/chat/completions');
        request.setMethod('POST');
        request.setHeader('Content-Type','application/json');
        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'model' => 'gpt-3.5-turbo',
                'messages' => new List<Map<String, String>>{
                    new Map<String, String>{ 'role' => 'user', 'content' => userInput }
                },
                'temperature' => 0.7
            }
        );
        request.setBody(requestBody);
        request.setTimeout(120000);
        try {
            HttpResponse response = http.send(request);
            responseString = response.getBody();
        } catch (Exception ex) {
            return 'Error: ' + ex.getMessage();
        }
        return responseString;
    }
}