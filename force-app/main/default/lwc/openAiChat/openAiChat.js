import { LightningElement, track } from 'lwc';
import openAIResponse from '@salesforce/apex/OpenAI_Integration.openAIResponse';
import xAIResponse from '@salesforce/apex/XAI_Integration.getXaiResponse';

export default class OpenAiChat extends LightningElement {
    @track userInput = '';
    @track response = '';

    handleChange(event) {
        this.userInput = event.target.value;
    }

    handleSubmit() {
        if (!this.userInput) return;

            openAIResponse({ userInput: this.userInput })
         //xAIResponse({ userInput: this.userInput })
            .then(result => {
                console.log('result : ',result);
                try {
                    let parsed = JSON.parse(result);
                    this.response = parsed.choices ? parsed.choices[0].message.content : result;
                } catch (e) {
                    this.response = result;
                }
            })
            .catch(error => {
                this.response = 'Error: ' + JSON.stringify(error);
            });
    }
}