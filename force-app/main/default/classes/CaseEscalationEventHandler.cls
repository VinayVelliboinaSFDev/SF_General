/**
 * CaseEscalationEventHandler
 * Handles Case_Escalation_Event__e events published by CaseEscalationEmailService.
 *
 * Execution context: Automated Process user (system-level).
 * This user has full access to setup objects including OrgWideEmailAddress,
 * making it safe to call EmailService.sendEscalationEmails() here even when
 * the original action was performed by an Experience Cloud portal user.
 */
public without sharing class CaseEscalationEventHandler {

    public static void handleEvents(
        List<Case_Escalation_Event__e> events
    ) {
        Email_Configuration__mdt config =
            Email_Configuration__mdt.getInstance('CaseEscalation');

        if (config == null) {
            return; // metadata not deployed — degrade gracefully
        }

        List<OrgWideEmailAddress> oweaList = [
            SELECT Id
            FROM   OrgWideEmailAddress
            WHERE  Address = :config.Sender_Email__c
            LIMIT  1
        ];

        if (oweaList.isEmpty()) {
            return; // org-wide address not found — degrade gracefully
        }

        Id oweaId = oweaList[0].Id;
        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();

        for (Case_Escalation_Event__e ev : events) {
            Messaging.SingleEmailMessage mail =
                new Messaging.SingleEmailMessage();

            mail.setToAddresses(
                new List<String>{ config.Recipient_Email__c }
            );
            mail.setSubject(
                'Escalated Case - ' + ev.Case_Number__c
            );
            mail.setPlainTextBody(
                'A case has been escalated and requires immediate attention.\n\n'
                + 'Case Number : ' + ev.Case_Number__c + '\n'
                + 'Subject     : ' + ev.Subject__c
            );
            mail.setOrgWideEmailAddressId(oweaId);

            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }
}
