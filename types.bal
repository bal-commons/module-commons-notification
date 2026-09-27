# Severity of a notification; independent of its free-form category.
public enum Severity {
    INFO,
    WARNING,
    ERROR,
    SUCCESS
}

# Whether a notification is addressed to one user or to everyone holding a role.
public enum RecipientType {
    USER,
    ROLE
}

# Which of the caller's boxes a listing covers: everything, the personal box, or role boxes.
public type Box "all"|"personal"|"role";

# A notification to send.
public type NewNotification record {|
    # USER for a personal box, ROLE for a role box
    RecipientType recipientType;
    # User ID or role name
    string recipientId;
    # Severity
    Severity severity = INFO;
    # Free-form grouping, e.g. `maintenance.escalation`
    string category?;
    # Short headline
    string title;
    # Longer text
    string body?;
    # Link the UI opens when the notification is clicked
    string actionUrl?;
    # Ties the notification to a case or workflow instance
    string correlationId?;
    # Who sent it; defaults to the caller's user ID
    string sender?;
    # Structured data for the UI
    json payload?;
    # RFC 3339 time after which the notification is hidden and purged
    string expiresAt?;
    # Makes retries safe: a second send with the same key returns the first notification
    string idempotencyKey?;
|};

# A stored notification.
public type Notification record {|
    # ULID; sorts by creation time
    string id;
    # USER or ROLE
    RecipientType recipientType;
    # User ID or role name
    string recipientId;
    # Severity
    Severity severity;
    # Free-form grouping
    string category?;
    # Short headline
    string title;
    # Longer text
    string body?;
    # Link the UI opens when the notification is clicked
    string actionUrl?;
    # Correlation ID of the case or workflow instance
    string correlationId?;
    # Who sent it
    string sender?;
    # Structured data for the UI
    json payload?;
    # RFC 3339 creation time
    string createdAt;
    # RFC 3339 expiry time
    string expiresAt?;
    # Whether the caller has read it; absent where there is no single reader (send, admin listing)
    boolean read?;
    # RFC 3339 time the caller read it
    string readAt?;
|};

# One page of notifications, newest first.
public type NotificationPage record {|
    # Notifications on this page
    Notification[] items;
    # Pass as `cursor` for the next page; absent on the last page
    string nextCursor?;
|};

# Filters for listing the caller's notifications.
public type ListOptions record {|
    # Which boxes to include
    Box box?;
    # Only this role's box (implies `box = "role"`)
    string role?;
    # Only this severity
    Severity severity?;
    # Only this category
    string category?;
    # Only this correlation ID
    string correlationId?;
    # Only read (`true`) or unread (`false`) notifications
    boolean read?;
    # `nextCursor` of the previous page
    string? cursor = ();
    # Page size
    int 'limit?;
|};

# Filters for listing any recipient's notifications (admin).
public type AdminListOptions record {|
    # Only this recipient type
    RecipientType recipientType?;
    # Only this recipient
    string recipientId?;
    # Only this severity
    Severity severity?;
    # Only this category
    string category?;
    # Only this correlation ID
    string correlationId?;
    # `nextCursor` of the previous page
    string? cursor = ();
    # Page size
    int 'limit?;
|};

# Selects the notifications `markAllRead` marks.
public type ReadAllFilter record {|
    # Which boxes to include
    Box box?;
    # Only this role's box
    string role?;
    # Only this category
    string category?;
    # Only this correlation ID
    string correlationId?;
|};

# Result of `markAllRead`.
public type ReadAllResult record {|
    # Number of notifications newly marked read
    int count;
|};

# Unread notifications visible to the caller.
public type UnreadCount record {|
    # All unread
    int total;
    # Unread in the personal box
    int personal;
    # Unread per role box, keyed by role
    map<int> roles;
|};

# Single-use ticket that authenticates an SSE stream through its URL.
public type StreamTicket record {|
    # Pass as the `ticket` query parameter of `/stream`
    string ticket;
    # Seconds until the ticket expires
    int expiresIn;
|};

# SSE event carrying a new visible notification; its ID is the notification ID.
public const EVENT_CREATED = "notification.created";
# SSE event sent to the reader when a notification is marked read.
public const EVENT_READ = "notification.read";
# SSE event sent to the reader when a notification is marked unread.
public const EVENT_UNREAD = "notification.unread";
# SSE event sent to the reader after `markAllRead`.
public const EVENT_READ_ALL = "notification.read-all";
# SSE event sent to the recipients when an admin deletes a notification.
public const EVENT_DELETED = "notification.deleted";
