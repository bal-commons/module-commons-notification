import ballerina/sql;
import ballerinax/java.jdbc;
import commons/service_commons;
import commons/service_commons.auth as sauth;
import commons/service_commons.db as sdb;
import commons/notification;

const BATCH_SIZE = 500;

type ItemRow record {|
    string id;
    string recipient_type;
    string recipient_id;
    string severity;
    string? category;
    string title;
    string? body;
    string? action_url;
    string? correlation_id;
    string? sender;
    string? payload;
    int created_at;
    int? expires_at;
    int? read_at = ();
|};

type UnreadRow record {|
    string recipient_type;
    string recipient_id;
    int unread;
|};

// Filters of the caller's inbox; `read` is ignored by `markAllRead`.
type InboxFilter record {|
    notification:Box box = "all";
    string? role = ();
    string? severity = ();
    string? category = ();
    string? correlationId = ();
    boolean? read = ();
|};

type AdminFilter record {|
    string? recipientType = ();
    string? recipientId = ();
    string? severity = ();
    string? category = ();
    string? correlationId = ();
|};

isolated class Store {
    private final jdbc:Client db;
    private final string ns;
    private final string itemTable;
    private final string readTable;

    isolated function init(jdbc:Client db, string ns, string prefix) {
        self.db = db;
        self.ns = ns;
        self.itemTable = prefix + "item";
        self.readTable = prefix + "read";
    }

    // Stores a notification; a repeated idempotency key returns the stored one with `false`.
    isolated function insert(notification:NewNotification input, string sender)
            returns [notification:Notification, boolean]|error {
        string id = service_commons:newId();
        string? expiresAt = input?.expiresAt;
        json payload = input?.payload;
        sql:ExecutionResult|sql:Error result = self.db->execute(sql:queryConcat(`INSERT INTO `, sdb:ident(self.itemTable),
            ` (id, ns, idempotency_key, recipient_type, recipient_id, severity, category, title, body, action_url,
               correlation_id, sender, payload, created_at, expires_at) VALUES (${id}, ${self.ns},
               ${input?.idempotencyKey}, ${input.recipientType}, ${input.recipientId}, ${input.severity},
               ${input?.category}, ${input.title}, ${input?.body}, ${input?.actionUrl}, ${input?.correlationId},
               ${input?.sender ?: sender}, ${payload is () ? () : payload.toJsonString()}, ${service_commons:nowMillis()},
               ${expiresAt is string ? check service_commons:fromIso(expiresAt) : ()})`));
        string? key = input?.idempotencyKey;
        if result is sql:Error {
            if key is string && sdb:isDuplicateKey(result) {
                ItemRow existing = check self.db->queryRow(sql:queryConcat(`SELECT `, columns(), ` FROM `,
                    sdb:ident(self.itemTable), ` n WHERE n.ns = ${self.ns} AND n.idempotency_key = ${key}`));
                return [check toNotification(existing, false), false];
            }
            return result;
        }
        ItemRow created = check self.db->queryRow(sql:queryConcat(`SELECT `, columns(), ` FROM `,
            sdb:ident(self.itemTable), ` n WHERE n.id = ${id}`));
        return [check toNotification(created, false), true];
    }

    isolated function list(sauth:CallerIdentity caller, InboxFilter filter, string? cursor, int 'limit)
            returns notification:NotificationPage|error {
        sql:ParameterizedQuery query = sql:queryConcat(self.inbox(caller), inboxFilter(filter));
        if cursor is string {
            query = sql:queryConcat(query, ` AND n.id < ${cursor}`);
        }
        ItemRow[] rows = check self.fetch(sql:queryConcat(query, ` ORDER BY n.id DESC LIMIT ${'limit + 1}`));
        return page(rows, 'limit, true);
    }

    isolated function find(sauth:CallerIdentity caller, string id) returns notification:Notification?|error {
        ItemRow[] rows = check self.fetch(sql:queryConcat(self.inbox(caller), ` AND n.id = ${id}`));
        return rows.length() == 0 ? () : check toNotification(rows[0], true);
    }

    // Marks a visible notification read; marking it again keeps the first read time.
    isolated function markRead(sauth:CallerIdentity caller, string id) returns notification:Notification?|error {
        notification:Notification? visible = check self.find(caller, id);
        if visible is () || visible.read == true {
            return visible;
        }
        sql:ExecutionResult|sql:Error result = self.db->execute(sql:queryConcat(`INSERT INTO `,
            sdb:ident(self.readTable), ` (user_id, notification_id, read_at) VALUES (${caller.userId}, ${id},
            ${service_commons:nowMillis()})`));
        if result is sql:Error && !sdb:isDuplicateKey(result) {
            return result;
        }
        return self.find(caller, id);
    }

    isolated function markUnread(sauth:CallerIdentity caller, string id) returns notification:Notification?|error {
        notification:Notification? visible = check self.find(caller, id);
        if visible is () {
            return ();
        }
        _ = check self.db->execute(sql:queryConcat(`DELETE FROM `, sdb:ident(self.readTable),
            ` WHERE user_id = ${caller.userId} AND notification_id = ${id}`));
        return self.find(caller, id);
    }

    isolated function markAllRead(sauth:CallerIdentity caller, InboxFilter filter) returns int|error {
        InboxFilter unread = filter.clone();
        unread.read = false;
        int count = 0;
        while true {
            ItemRow[] rows = check self.fetch(sql:queryConcat(self.inbox(caller), inboxFilter(unread),
                ` ORDER BY n.id LIMIT ${BATCH_SIZE}`));
            string[] batch = rows.map(row => row.id);
            int now = service_commons:nowMillis();
            foreach string id in batch {
                sql:ExecutionResult|sql:Error result = self.db->execute(sql:queryConcat(`INSERT INTO `,
                    sdb:ident(self.readTable), ` (user_id, notification_id, read_at) VALUES (${caller.userId},
                    ${id}, ${now})`));
                if result is sql:Error && !sdb:isDuplicateKey(result) {
                    return result;
                }
            }
            count += batch.length();
            if batch.length() < BATCH_SIZE {
                return count;
            }
        }
    }

    isolated function unreadCount(sauth:CallerIdentity caller) returns notification:UnreadCount|error {
        stream<UnreadRow, sql:Error?> rows = self.db->query(sql:queryConcat(`SELECT n.recipient_type,
            n.recipient_id, COUNT(*) AS unread FROM `, sdb:ident(self.itemTable), ` n LEFT JOIN `,
            sdb:ident(self.readTable), ` r ON r.notification_id = n.id AND r.user_id = ${caller.userId}
            WHERE n.ns = ${self.ns} AND `, visibleTo(caller), ` AND `, notExpired(), ` AND r.read_at IS NULL
            GROUP BY n.recipient_type, n.recipient_id`));
        notification:UnreadCount counts = {total: 0, personal: 0, roles: {}};
        check from UnreadRow row in rows
            do {
                counts.total += row.unread;
                if row.recipient_type == notification:USER {
                    counts.personal += row.unread;
                } else {
                    counts.roles[row.recipient_id] = row.unread;
                }
            };
        return counts;
    }

    // Visible notifications created after `lastId`, oldest first, for SSE replay.
    isolated function replay(sauth:CallerIdentity caller, string lastId, int 'limit)
            returns notification:Notification[]|error {
        ItemRow[] rows = check self.fetch(sql:queryConcat(self.inbox(caller),
            ` AND n.id > ${lastId} ORDER BY n.id LIMIT ${'limit}`));
        return from ItemRow row in rows select check toNotification(row, true);
    }

    isolated function adminList(AdminFilter filter, string? cursor, int 'limit)
            returns notification:NotificationPage|error {
        sql:ParameterizedQuery query = sql:queryConcat(`SELECT `, columns(), ` FROM `, sdb:ident(self.itemTable),
            ` n WHERE n.ns = ${self.ns}`);
        string? recipientType = filter.recipientType;
        if recipientType is string {
            query = sql:queryConcat(query, ` AND n.recipient_type = ${recipientType}`);
        }
        string? recipientId = filter.recipientId;
        if recipientId is string {
            query = sql:queryConcat(query, ` AND n.recipient_id = ${recipientId}`);
        }
        query = sql:queryConcat(query, attributeFilter(filter.severity, filter.category, filter.correlationId));
        if cursor is string {
            query = sql:queryConcat(query, ` AND n.id < ${cursor}`);
        }
        ItemRow[] rows = check self.fetch(sql:queryConcat(query, ` ORDER BY n.id DESC LIMIT ${'limit + 1}`));
        return page(rows, 'limit, false);
    }

    // Deletes a notification and its read state for everyone; returns it, or `()` if it did not exist.
    isolated function delete(string id) returns notification:Notification?|error {
        ItemRow[] rows = check self.fetch(sql:queryConcat(`SELECT `, columns(), ` FROM `, sdb:ident(self.itemTable),
            ` n WHERE n.ns = ${self.ns} AND n.id = ${id}`));
        if rows.length() == 0 {
            return ();
        }
        _ = check self.db->execute(sql:queryConcat(`DELETE FROM `, sdb:ident(self.readTable),
            ` WHERE notification_id = ${id}`));
        _ = check self.db->execute(sql:queryConcat(`DELETE FROM `, sdb:ident(self.itemTable),
            ` WHERE ns = ${self.ns} AND id = ${id}`));
        return toNotification(rows[0], false);
    }

    // Deletes expired notifications and those created before `createdBefore`.
    isolated function purge(int createdBefore) returns int|error {
        sql:ParameterizedQuery purgeable = sql:queryConcat(`ns = ${self.ns} AND (created_at < ${createdBefore}
            OR (expires_at IS NOT NULL AND expires_at <= ${service_commons:nowMillis()}))`);
        _ = check self.db->execute(sql:queryConcat(`DELETE FROM `, sdb:ident(self.readTable),
            ` WHERE notification_id IN (SELECT id FROM `, sdb:ident(self.itemTable), ` WHERE `, purgeable, `)`));
        sql:ExecutionResult result = check self.db->execute(sql:queryConcat(`DELETE FROM `,
            sdb:ident(self.itemTable), ` WHERE `, purgeable));
        return result.affectedRowCount ?: 0;
    }

    // Selects the caller's visible, unexpired notifications with their read state.
    isolated function inbox(sauth:CallerIdentity caller) returns sql:ParameterizedQuery {
        return sql:queryConcat(`SELECT `, columns(), `, r.read_at FROM `, sdb:ident(self.itemTable), ` n LEFT JOIN `,
            sdb:ident(self.readTable), ` r ON r.notification_id = n.id AND r.user_id = ${caller.userId}
            WHERE n.ns = ${self.ns} AND `, visibleTo(caller), ` AND `, notExpired());
    }

    isolated function fetch(sql:ParameterizedQuery query) returns ItemRow[]|error {
        stream<ItemRow, sql:Error?> rows = self.db->query(query);
        return from ItemRow row in rows select row;
    }
}

isolated function columns() returns sql:ParameterizedQuery => sdb:raw(string `n.id, n.recipient_type,
    n.recipient_id, n.severity, n.category, n.title, n.body, n.action_url, n.correlation_id, n.sender, n.payload,
    n.created_at, n.expires_at`);

// Personal notifications of the caller, plus those of every role in the caller's token.
isolated function visibleTo(sauth:CallerIdentity caller) returns sql:ParameterizedQuery {
    sql:ParameterizedQuery query = `((n.recipient_type = 'USER' AND n.recipient_id = ${caller.userId})`;
    if caller.roles.length() > 0 {
        query = sql:queryConcat(query, ` OR (n.recipient_type = 'ROLE' AND n.recipient_id IN (`,
            sql:arrayFlattenQuery(caller.roles), `))`);
    }
    return sql:queryConcat(query, `)`);
}

isolated function notExpired() returns sql:ParameterizedQuery =>
    `(n.expires_at IS NULL OR n.expires_at > ${service_commons:nowMillis()})`;

isolated function inboxFilter(InboxFilter filter) returns sql:ParameterizedQuery {
    sql:ParameterizedQuery query = ``;
    string? role = filter.role;
    if role is string {
        query = ` AND n.recipient_type = 'ROLE' AND n.recipient_id = ${role}`;
    } else if filter.box == "personal" {
        query = ` AND n.recipient_type = 'USER'`;
    } else if filter.box == "role" {
        query = ` AND n.recipient_type = 'ROLE'`;
    }
    query = sql:queryConcat(query, attributeFilter(filter.severity, filter.category, filter.correlationId));
    boolean? read = filter.read;
    if read is boolean {
        query = sql:queryConcat(query, read ? ` AND r.read_at IS NOT NULL` : ` AND r.read_at IS NULL`);
    }
    return query;
}

isolated function attributeFilter(string? severity, string? category, string? correlationId)
        returns sql:ParameterizedQuery {
    sql:ParameterizedQuery query = ``;
    if severity is string {
        query = sql:queryConcat(query, ` AND n.severity = ${severity}`);
    }
    if category is string {
        query = sql:queryConcat(query, ` AND n.category = ${category}`);
    }
    if correlationId is string {
        query = sql:queryConcat(query, ` AND n.correlation_id = ${correlationId}`);
    }
    return query;
}

// Builds a page from `limit + 1` rows; the extra row only signals that another page exists.
isolated function page(ItemRow[] rows, int 'limit, boolean withRead) returns notification:NotificationPage|error {
    ItemRow[] items = rows.length() > 'limit ? rows.slice(0, 'limit) : rows;
    notification:NotificationPage result = {items: from ItemRow row in items select check toNotification(row, withRead)};
    if rows.length() > 'limit {
        result.nextCursor = items[items.length() - 1].id;
    }
    return result;
}

isolated function toNotification(ItemRow row, boolean withRead) returns notification:Notification|error {
    notification:Notification result = {
        id: row.id,
        recipientType: check row.recipient_type.ensureType(),
        recipientId: row.recipient_id,
        severity: check row.severity.ensureType(),
        title: row.title,
        createdAt: service_commons:toIso(row.created_at)
    };
    string? category = row.category;
    if category is string {
        result.category = category;
    }
    string? body = row.body;
    if body is string {
        result.body = body;
    }
    string? actionUrl = row.action_url;
    if actionUrl is string {
        result.actionUrl = actionUrl;
    }
    string? correlationId = row.correlation_id;
    if correlationId is string {
        result.correlationId = correlationId;
    }
    string? sender = row.sender;
    if sender is string {
        result.sender = sender;
    }
    string? payload = row.payload;
    if payload is string {
        result.payload = check payload.fromJsonString();
    }
    int? expiresAt = row.expires_at;
    if expiresAt is int {
        result.expiresAt = service_commons:toIso(expiresAt);
    }
    if withRead {
        int? readAt = row.read_at;
        result.read = readAt is int;
        if readAt is int {
            result.readAt = service_commons:toIso(readAt);
        }
    }
    return result;
}
