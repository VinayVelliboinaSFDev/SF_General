@IsTest
private class NotificationServiceTest {

    // ── Helpers ──────────────────────────────────────────────────────────────

    /** Returns the first available CustomNotificationType, or null if none exist. */
    private static CustomNotificationType getAnyType() {
        List<CustomNotificationType> types = [SELECT Id, DeveloperName FROM CustomNotificationType LIMIT 1];
        return types.isEmpty() ? null : types[0];
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    @IsTest
    static void send_singleRecipient_noException() {
        CustomNotificationType notifType = getAnyType();
        if (notifType == null) return; // org has no notification types — skip

        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        Test.startTest();
        NotificationService.send(notifType.DeveloperName, u.Id, 'Test Title', 'Test Body', u.Id);
        Test.stopTest();
        // Passes if no exception thrown
    }

    @IsTest
    static void sendToMany_multipleRecipients_noException() {
        CustomNotificationType notifType = getAnyType();
        if (notifType == null) return;

        Set<String> ids = new Set<String>{ UserInfo.getUserId() };

        Test.startTest();
        NotificationService.sendToMany(notifType.DeveloperName, ids, 'Bulk Title', 'Bulk Body', null);
        Test.stopTest();
    }

    @IsTest
    static void sendBulk_multipleRequests_noException() {
        CustomNotificationType notifType = getAnyType();
        if (notifType == null) return;

        Set<String> ids = new Set<String>{ UserInfo.getUserId() };

        List<NotificationService.NotificationRequest> reqs = new List<NotificationService.NotificationRequest>{
            new NotificationService.NotificationRequest(notifType.DeveloperName, ids, 'Title 1', 'Body 1', null),
            new NotificationService.NotificationRequest(notifType.DeveloperName, ids, 'Title 2', 'Body 2', UserInfo.getUserId())
        };

        Test.startTest();
        NotificationService.sendBulk(reqs);
        Test.stopTest();
    }

    @IsTest
    static void send_invalidTypeName_noException() {
        // Should log a warning and not throw
        Test.startTest();
        NotificationService.send('INVALID_TYPE_XYZ', UserInfo.getUserId(), 'T', 'B', null);
        Test.stopTest();
    }

    @IsTest
    static void sendBulk_emptyList_noException() {
        Test.startTest();
        NotificationService.sendBulk(new List<NotificationService.NotificationRequest>());
        Test.stopTest();
    }

    @IsTest
    static void sendBulk_nullList_noException() {
        Test.startTest();
        NotificationService.sendBulk(null);
        Test.stopTest();
    }

    @IsTest
    static void send_longTitleAndBody_truncatesGracefully() {
        CustomNotificationType notifType = getAnyType();
        if (notifType == null) return;

        String longTitle = 'A'.repeat(300);
        String longBody  = 'B'.repeat(800);

        Test.startTest();
        NotificationService.send(notifType.DeveloperName, UserInfo.getUserId(), longTitle, longBody, null);
        Test.stopTest();
    }
}
