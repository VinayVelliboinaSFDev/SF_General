/**
 * Reusable service for sending Salesforce Bell (In-App) Notifications.
 * Uses CustomNotificationType + Messaging.CustomNotification API.
 *
 * Usage:
 *   NotificationService.send('YourNotifTypeDeveloperName', targetUserId, 'Title', 'Body', recordId);
 *   NotificationService.sendToMany('YourNotifTypeDeveloperName', userIdSet, 'Title', 'Body', recordId);
 *   NotificationService.sendBulk(List<NotificationService.NotificationRequest>);
 */
public with sharing class NotificationService {

    // ─── Inner Request DTO ───────────────────────────────────────────────────

    public class NotificationRequest {
        public String  typeDeveloperName;   // CustomNotificationType DeveloperName
        public Set<String> recipientIds;    // User or Group Ids
        public String  title;
        public String  body;
        public String  targetId;            // Record page to open on click (optional)

        public NotificationRequest(
            String typeDeveloperName,
            Set<String> recipientIds,
            String title,
            String body,
            String targetId
        ) {
            this.typeDeveloperName = typeDeveloperName;
            this.recipientIds      = recipientIds;
            this.title             = title;
            this.body              = body;
            this.targetId          = targetId;
        }
    }

    // ─── Public API ──────────────────────────────────────────────────────────

    /** Send to a single user/group. */
    public static void send(
        String typeDeveloperName,
        String recipientId,
        String title,
        String body,
        String targetId
    ) {
        sendToMany(typeDeveloperName, new Set<String>{ recipientId }, title, body, targetId);
    }

    /** Send to multiple users/groups in one call. */
    public static void sendToMany(
        String typeDeveloperName,
        Set<String> recipientIds,
        String title,
        String body,
        String targetId
    ) {
        sendBulk(new List<NotificationRequest>{
            new NotificationRequest(typeDeveloperName, recipientIds, title, body, targetId)
        });
    }

    /** Bulk send — one DML per distinct CustomNotificationType (governor-friendly). */
    public static void sendBulk(List<NotificationRequest> requests) {
        if (requests == null || requests.isEmpty()) return;

        // Cache type lookups to avoid repeated SOQL
        Map<String, Id> typeCache = new Map<String, Id>();

        for (NotificationRequest req : requests) {
            if (String.isBlank(req.typeDeveloperName) || req.recipientIds == null || req.recipientIds.isEmpty()) {
                continue;
            }

            Id typeId = resolveTypeId(req.typeDeveloperName, typeCache);
            if (typeId == null) continue;

            Messaging.CustomNotification notif = buildNotification(typeId, req.title, req.body, req.targetId);

            try {
                notif.send(req.recipientIds);
            } catch (Exception e) {
                // Log and continue so one bad recipient set doesn't block others
                System.debug(LoggingLevel.ERROR,
                    'NotificationService.sendBulk failed for type ' + req.typeDeveloperName +
                    ' | recipients: ' + req.recipientIds + ' | error: ' + e.getMessage());
            }
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────

    private static Id resolveTypeId(String developerName, Map<String, Id> cache) {
        if (cache.containsKey(developerName)) return cache.get(developerName);

        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        Id typeId = types.isEmpty() ? null : types[0].Id;

        if (typeId == null) {
            System.debug(LoggingLevel.WARN,
                'NotificationService: CustomNotificationType not found — ' + developerName);
        }

        cache.put(developerName, typeId);
        return typeId;
    }

    private static Messaging.CustomNotification buildNotification(
        Id typeId, String title, String body, String targetId
    ) {
        Messaging.CustomNotification notif = new Messaging.CustomNotification();
        notif.setNotificationTypeId(typeId);
        notif.setTitle(String.isBlank(title) ? 'Notification' : title.abbreviate(255));
        notif.setBody(String.isBlank(body)   ? ''            : body.abbreviate(750));

        if (String.isNotBlank(targetId)) {
            notif.setTargetId(targetId);
        }

        return notif;
    }
}
