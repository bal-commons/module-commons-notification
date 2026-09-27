import ballerina/http;
import commons/service_commons;
import commons/service_commons.auth as sauth;
import commons/service_commons.sse;
import commons/notification;

final http:InterceptableService notificationService = @http:ServiceConfig {
    cors: {
        allowOrigins: corsAllowOrigins,
        allowHeaders: ["Authorization", "Content-Type", "Last-Event-ID", sauth:HEADER_USER_ID,
            sauth:HEADER_USER_ROLES, sauth:HEADER_USER_SCOPES, auth.apiKeyHeader],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    }
} isolated service object {

    public isolated function createInterceptors() returns [sauth:AuthInterceptor, service_commons:ErrorInterceptor] =>
        [new (authenticator, tickets), new];

    isolated resource function post notifications(http:RequestContext ctx,
            @http:Payload notification:NewNotification body)
            returns http:Created|http:Ok|http:BadRequest|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeSend);
        if caller is http:Forbidden {
            return caller;
        }
        string? invalid = validateNew(body);
        if invalid is string {
            return service_commons:badRequest(invalid);
        }
        [notification:Notification, boolean] [stored, created] = check store.insert(body, caller.userId);
        if !created {
            return <http:Ok>{body: stored};
        }
        notification:Notification unread = stored.clone();
        unread.read = false;
        hub.publish({id: stored.id, event: notification:EVENT_CREATED, data: unread},
            [target(stored.recipientType, stored.recipientId)]);
        return <http:Created>{body: stored, headers: {"Location": string `${basePath}/notifications/${stored.id}`}};
    }

    isolated resource function get notifications(http:RequestContext ctx, string box = "all", string? role = (),
            string? severity = (), string? category = (), string? correlationId = (), boolean? read = (),
            string? cursor = (), int 'limit = 20)
            returns notification:NotificationPage|http:BadRequest|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeRead);
        if caller is http:Forbidden {
            return caller;
        }
        if box !is notification:Box {
            return service_commons:badRequest("box must be all, personal or role");
        }
        string? invalid = validateSeverity(severity) ?: validateLimit('limit);
        if invalid is string {
            return service_commons:badRequest(invalid);
        }
        return store.list(caller, {box, role, severity, category, correlationId, read}, cursor, 'limit);
    }

    isolated resource function get notifications/unread\-count(http:RequestContext ctx)
            returns notification:UnreadCount|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeRead);
        if caller is http:Forbidden {
            return caller;
        }
        return store.unreadCount(caller);
    }

    isolated resource function post notifications/read\-all(http:RequestContext ctx,
            @http:Payload notification:ReadAllFilter? body) returns notification:ReadAllResult|http:BadRequest|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeRead);
        if caller is http:Forbidden {
            return caller;
        }
        notification:ReadAllFilter filter = body ?: {};
        int count = check store.markAllRead(caller, {
            box: filter.box ?: "all",
            role: filter?.role,
            category: filter?.category,
            correlationId: filter?.correlationId
        });
        if count > 0 {
            hub.publish({id: service_commons:newId(), event: notification:EVENT_READ_ALL, data: {count}},
                [target(notification:USER, caller.userId)]);
        }
        return {count};
    }

    isolated resource function get notifications/[string id](http:RequestContext ctx)
            returns notification:Notification|http:NotFound|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeRead);
        if caller is http:Forbidden {
            return caller;
        }
        return check store.find(caller, id) ?: service_commons:notFound(string `Notification ${id} not found`);
    }

    isolated resource function put notifications/[string id]/read(http:RequestContext ctx)
            returns notification:Notification|http:NotFound|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeRead);
        if caller is http:Forbidden {
            return caller;
        }
        notification:Notification? updated = check store.markRead(caller, id);
        if updated is () {
            return service_commons:notFound(string `Notification ${id} not found`);
        }
        hub.publish({id: service_commons:newId(), event: notification:EVENT_READ, data: {id, readAt: updated?.readAt}},
            [target(notification:USER, caller.userId)]);
        return updated;
    }

    isolated resource function delete notifications/[string id]/read(http:RequestContext ctx)
            returns notification:Notification|http:NotFound|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeRead);
        if caller is http:Forbidden {
            return caller;
        }
        notification:Notification? updated = check store.markUnread(caller, id);
        if updated is () {
            return service_commons:notFound(string `Notification ${id} not found`);
        }
        hub.publish({id: service_commons:newId(), event: notification:EVENT_UNREAD, data: {id}},
            [target(notification:USER, caller.userId)]);
        return updated;
    }

    isolated resource function delete notifications/[string id](http:RequestContext ctx)
            returns http:NoContent|http:NotFound|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeAdmin);
        if caller is http:Forbidden {
            return caller;
        }
        notification:Notification? deleted = check store.delete(id);
        if deleted is () {
            return service_commons:notFound(string `Notification ${id} not found`);
        }
        hub.publish({id: service_commons:newId(), event: notification:EVENT_DELETED, data: {id}},
            [target(deleted.recipientType, deleted.recipientId)]);
        return http:NO_CONTENT;
    }

    isolated resource function get admin/notifications(http:RequestContext ctx, string? recipientType = (),
            string? recipientId = (), string? severity = (), string? category = (), string? correlationId = (),
            string? cursor = (), int 'limit = 20)
            returns notification:NotificationPage|http:BadRequest|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeAdmin);
        if caller is http:Forbidden {
            return caller;
        }
        if recipientType !is () && recipientType !is notification:RecipientType {
            return service_commons:badRequest("recipientType must be USER or ROLE");
        }
        string? invalid = validateSeverity(severity) ?: validateLimit('limit);
        if invalid is string {
            return service_commons:badRequest(invalid);
        }
        return store.adminList({recipientType, recipientId, severity, category, correlationId}, cursor, 'limit);
    }

    isolated resource function post stream\-ticket(http:RequestContext ctx)
            returns notification:StreamTicket|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeRead);
        if caller is http:Forbidden {
            return caller;
        }
        return {ticket: tickets.issue(caller), expiresIn: tickets.ttlSeconds()};
    }

    // Streams new visible notifications. Browsers authenticate with `?ticket=`; after a reconnect, pass the
    // last received event ID as `Last-Event-ID` or `lastEventId` to replay what was missed.
    isolated resource function get 'stream(http:RequestContext ctx,
            @http:Header {name: "Last-Event-ID"} string? lastEventIdHeader, string? lastEventId = ())
            returns stream<http:SseEvent, error?>|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeRead);
        if caller is http:Forbidden {
            return caller;
        }
        string? replayFrom = lastEventIdHeader ?: lastEventId;
        sse:StreamEvent[] backlog = [];
        if replayFrom is string {
            notification:Notification[] missed = check store.replay(caller, replayFrom, replayLimit);
            backlog = from notification:Notification item in missed
                select {id: item.id, event: notification:EVENT_CREATED, data: item};
        }
        string[] targets = [target(notification:USER, caller.userId),
            ...from string role in caller.roles select target(notification:ROLE, role)];
        return hub.open(targets, backlog);
    }
};

// Admin operations need the scope itself, even when scopes are not enforced.
isolated function authorize(http:RequestContext ctx, string scope) returns sauth:CallerIdentity|http:Forbidden|error {
    sauth:CallerIdentity caller = check sauth:callerOf(ctx);
    boolean granted = scope == scopeAdmin ? sauth:holdsScope(caller, scope) : authenticator.hasScope(caller, scope);
    return granted ? caller : service_commons:forbidden(string `Requires scope '${scope}'`);
}

isolated function target(notification:RecipientType recipientType, string recipientId) returns string =>
    recipientType == notification:USER ? "user:" + recipientId : "role:" + recipientId;

isolated function validateNew(notification:NewNotification input) returns string? {
    if input.recipientId.trim() == "" || input.recipientId.length() > 255 {
        return "recipientId must be 1-255 characters";
    }
    if input.title.trim() == "" || input.title.length() > 500 {
        return "title must be 1-500 characters";
    }
    if (input?.category ?: "").length() > 128 {
        return "category must be at most 128 characters";
    }
    if (input?.actionUrl ?: "").length() > 2000 {
        return "actionUrl must be at most 2000 characters";
    }
    if (input?.idempotencyKey ?: "").length() > 255 {
        return "idempotencyKey must be at most 255 characters";
    }
    string? expiresAt = input?.expiresAt;
    if expiresAt is string && service_commons:fromIso(expiresAt) is error {
        return "expiresAt must be an RFC 3339 timestamp";
    }
    return ();
}

isolated function validateSeverity(string? severity) returns string? =>
    severity is () || severity is notification:Severity ? () : "severity must be INFO, WARNING, ERROR or SUCCESS";

isolated function validateLimit(int 'limit) returns string? =>
    'limit >= 1 && 'limit <= maxPageSize ? () : string `limit must be between 1 and ${maxPageSize}`;
