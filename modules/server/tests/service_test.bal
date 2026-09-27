import ballerina/http;
import ballerina/test;
import ballerinax/h2.driver as _;
import commons/notification;

const URL = "http://localhost:19100/notifications/v1";
const READ = "notification:read";

final notification:Client workflow = check new (URL, headers = {
    "x-user-id": "maintenance-workflow", "x-user-scopes": "notification:send notification:admin"
});

function persona(string userId, string roles = "", string scopes = READ) returns notification:Client|error =>
    new (URL, headers = {"x-user-id": userId, "x-user-roles": roles, "x-user-scopes": scopes});

function statusOf(any|error result) returns int {
    if result is http:ApplicationResponseError {
        return result.detail().statusCode;
    }
    return result is error ? -1 : 200;
}

function toUser(string userId, string title = "hello") returns notification:NewNotification =>
    {recipientType: notification:USER, recipientId: userId, title};

function toRole(string role, string title = "hello") returns notification:NewNotification =>
    {recipientType: notification:ROLE, recipientId: role, title};

function items(notification:Client reader, notification:ListOptions options = {})
        returns notification:Notification[]|error {
    notification:NotificationPage page = check reader->list(options);
    return page.items;
}

function titles(notification:NotificationPage page) returns string[] => page.items.map(n => n.title);

// Skips comments (`connected`, `keepalive`), as a browser's EventSource does.
function nextEvent(stream<http:SseEvent, error?> events) returns http:SseEvent|error {
    while true {
        record {|http:SseEvent value;|}? next = check events.next();
        if next is () {
            return error("stream ended");
        }
        if next.value.comment is () {
            return next.value;
        }
    }
}

@test:Config
function personalNotificationReachesOnlyItsUser() returns error? {
    notification:Notification sent = check workflow->send({
        recipientType: notification:USER, recipientId: "tara", title: "Photo received", body: "Thanks",
        severity: notification:SUCCESS, category: "maintenance.evidence", correlationId: "case-1",
        actionUrl: "/cases/case-1", payload: {caseId: "case-1"}
    });
    test:assertEquals(sent?.sender, "maintenance-workflow");
    test:assertEquals(sent?.read, ());

    notification:Client tara = check persona("tara", "Tenant");
    notification:Notification[] inbox = check items(tara);
    test:assertEquals(inbox.length(), 1);
    test:assertEquals(inbox[0].id, sent.id);
    test:assertEquals(inbox[0]?.payload, {caseId: "case-1"});
    test:assertEquals(inbox[0]?.read, false);

    notification:Client carlos = check persona("carlos", "Contractor");
    test:assertEquals((check items(carlos)).length(), 0);
    notification:Notification|error peek = carlos->get(sent.id);
    test:assertEquals(statusOf(peek), 404);
}

@test:Config
function roleNotificationIsVisibleByClaimsAndReadPerUser() returns error? {
    notification:Notification sent = check workflow->send(toRole("Finance", "Approve quote"));
    notification:Client fernando = check persona("fernando", "Finance,Staff");
    notification:Client fiona = check persona("fiona", "Finance");
    notification:Client tara = check persona("tara2", "Tenant");

    notification:Notification seen = check fernando->get(sent.id);
    test:assertEquals(seen?.read, false);
    test:assertEquals((check items(tara)).length(), 0);

    notification:Notification read = check fernando->markRead(sent.id);
    test:assertEquals(read?.read, true);
    test:assertTrue(read?.readAt is string);
    notification:Notification forFiona = check fiona->get(sent.id);
    test:assertEquals(forFiona?.read, false, "read state is per user");

    notification:Notification again = check fernando->markRead(sent.id);
    test:assertEquals(again?.readAt, read?.readAt, "marking read twice keeps the first read time");

    notification:Notification unread = check fernando->markUnread(sent.id);
    test:assertEquals(unread?.read, false);
    notification:Notification|error intruder = tara->markRead(sent.id);
    test:assertEquals(statusOf(intruder), 404, "cannot mark what you cannot see");
}

@test:Config
function unreadCountSplitsPersonalAndRoles() returns error? {
    _ = check workflow->send(toUser("priya"));
    _ = check workflow->send(toUser("priya"));
    _ = check workflow->send(toRole("PropertyManager"));
    notification:Notification dispatch = check workflow->send(toRole("Dispatch"));
    notification:Client priya = check persona("priya", "PropertyManager,Dispatch");
    _ = check priya->markRead(dispatch.id);
    notification:UnreadCount counts = check priya->unreadCount();
    test:assertEquals(counts, {total: 3, personal: 2, roles: {"PropertyManager": 1}});
}

@test:Config
function markAllReadHonoursTheFilter() returns error? {
    _ = check workflow->send(toUser("rita"));
    _ = check workflow->send(toUser("rita"));
    _ = check workflow->send(toRole("Auditors"));
    notification:Client rita = check persona("rita", "Auditors");
    notification:ReadAllResult personal = check rita->markAllRead(box = "personal");
    test:assertEquals(personal.count, 2);
    notification:UnreadCount left = check rita->unreadCount();
    test:assertEquals(left.total, 1);
    notification:ReadAllResult rest = check rita->markAllRead();
    test:assertEquals(rest.count, 1);
    notification:ReadAllResult none = check rita->markAllRead();
    test:assertEquals(none.count, 0);
}

@test:Config
function listFiltersByBoxRoleSeverityAndReadState() returns error? {
    _ = check workflow->send({recipientType: notification:USER, recipientId: "sam", title: "hello", severity: notification:WARNING, correlationId: "c-9"});
    notification:Notification roleNote = check workflow->send({recipientType: notification:ROLE, recipientId: "Night", title: "hello", category: "shift"});
    _ = check workflow->send(toRole("Day"));
    notification:Client sam = check persona("sam", "Night,Day");

    test:assertEquals((check items(sam)).length(), 3);
    test:assertEquals((check items(sam, {box: "personal"})).length(), 1);
    test:assertEquals((check items(sam, {box: "role"})).length(), 2);
    test:assertEquals((check items(sam, {role: "Night"}))[0].id, roleNote.id);
    test:assertEquals((check items(sam, {severity: notification:WARNING})).length(), 1);
    test:assertEquals((check items(sam, {category: "shift"})).length(), 1);
    test:assertEquals((check items(sam, {correlationId: "c-9"})).length(), 1);
    _ = check sam->markRead(roleNote.id);
    test:assertEquals((check items(sam, {read: true})).length(), 1);
    test:assertEquals((check items(sam, {read: false})).length(), 2);
}

@test:Config
function pagesAreNewestFirstWithCursor() returns error? {
    foreach int i in 1 ... 5 {
        _ = check workflow->send(toUser("paula", string `n${i}`));
    }
    notification:Client paula = check persona("paula");
    notification:NotificationPage first = check paula->list('limit = 2);
    test:assertEquals(titles(first), ["n5", "n4"]);
    notification:NotificationPage second = check paula->list('limit = 2, cursor = first?.nextCursor);
    test:assertEquals(titles(second), ["n3", "n2"]);
    notification:NotificationPage last = check paula->list('limit = 2, cursor = second?.nextCursor);
    test:assertEquals(titles(last), ["n1"]);
    test:assertEquals(last?.nextCursor, ());
}

@test:Config
function idempotencyKeyMakesRetriesSafe() returns error? {
    notification:NewNotification note = {recipientType: notification:USER, recipientId: "ivan", title: "hello", idempotencyKey: "wf-42/step-3"};
    notification:Notification first = check workflow->send(note);
    notification:Notification second = check workflow->send(note);
    test:assertEquals(second.id, first.id);
    notification:Client ivan = check persona("ivan");
    test:assertEquals((check items(ivan)).length(), 1);
}

@test:Config
function expiredNotificationsAreHiddenAndPurged() returns error? {
    notification:Notification gone = check workflow->send({recipientType: notification:USER, recipientId: "eve", title: "hello", expiresAt: "2020-01-01T00:00:00Z"});
    _ = check workflow->send(toUser("eve"));
    notification:Client eve = check persona("eve");
    test:assertEquals((check items(eve)).length(), 1);
    test:assertTrue(check store.purge(0) >= 1);
    error? deleted = workflow->delete(gone.id);
    test:assertTrue(deleted is error, "purged notification no longer exists");
}

@test:Config
function scopesAreEnforced() returns error? {
    notification:Client reader = check persona("rob");
    notification:Notification|error sent = reader->send(toUser("rob"));
    test:assertEquals(statusOf(sent), 403);
    notification:NotificationPage|error listed = reader->adminList();
    test:assertEquals(statusOf(listed), 403);
    notification:Client sender = check persona("sally", scopes = "notification:send");
    notification:NotificationPage|error own = sender->list();
    test:assertEquals(statusOf(own), 403);
}

@test:Config
function invalidInputIsRejected() returns error? {
    notification:Notification|error untitled = workflow->send(toUser("x", ""));
    test:assertEquals(statusOf(untitled), 400);
    notification:Notification|error badExpiry = workflow->send({recipientType: notification:USER, recipientId: "x", title: "hello", expiresAt: "tomorrow"});
    test:assertEquals(statusOf(badExpiry), 400);
    notification:Client x = check persona("x");
    notification:NotificationPage|error tooMany = x->list('limit = 1000);
    test:assertEquals(statusOf(tooMany), 400);

    http:Client raw = check new (URL);
    http:Response badBox = check raw->get("/notifications?box=inbox", {"x-user-id": "x", "x-user-scopes": READ});
    test:assertEquals(badBox.statusCode, 400);
    http:Response badType = check raw->post("/notifications", {recipientType: "TEAM", recipientId: "a", title: "t"},
        {"x-user-id": "w"});
    test:assertEquals(badType.statusCode, 400);
    json body = check badType.getJsonPayload();
    test:assertEquals(check body.code, "BAD_REQUEST");
}

@test:Config
function adminListsAndDeletesAnyRecipient() returns error? {
    notification:Notification sent = check workflow->send({recipientType: notification:ROLE, recipientId: "Janitors", title: "hello", correlationId: "c-admin"});
    notification:NotificationPage page = check workflow->adminList(recipientType = notification:ROLE,
        recipientId = "Janitors");
    test:assertEquals(page.items.map(n => n.id), [sent.id]);
    test:assertEquals(page.items[0]?.read, ());
    check workflow->delete(sent.id);
    notification:Client jan = check persona("jan", "Janitors");
    test:assertEquals((check items(jan)).length(), 0);
}

@test:Config
function streamDeliversVisibleNotificationsLive() returns error? {
    notification:Client olga = check persona("olga", "Plumbers");
    stream<http:SseEvent, error?> events = check olga->events();
    _ = check workflow->send(toUser("someone-else"));
    notification:Notification forRole = check workflow->send(toRole("Plumbers", "Leak at 4B"));
    http:SseEvent event = check nextEvent(events);
    test:assertEquals(event.id, forRole.id);
    test:assertEquals(event.event, notification:EVENT_CREATED);
    json data = check (event.data ?: "").fromJsonString();
    test:assertEquals(check data.title, "Leak at 4B");
    test:assertEquals(check data.read, false);

    _ = check olga->markRead(forRole.id);
    http:SseEvent readEvent = check nextEvent(events);
    test:assertEquals(readEvent.event, notification:EVENT_READ);
    check events.close();
}

@test:Config
function streamTicketAuthenticatesOnceAndReplays() returns error? {
    notification:Notification first = check workflow->send(toUser("tim", "first"));
    notification:Notification second = check workflow->send(toUser("tim", "second"));
    notification:Client tim = check persona("tim");
    notification:StreamTicket ticket = check tim->streamTicket();

    http:Client browser = check new (URL);
    stream<http:SseEvent, error?> events = check browser->get(
        string `/stream?ticket=${ticket.ticket}&lastEventId=${first.id}`);
    http:SseEvent replayed = check nextEvent(events);
    test:assertEquals(replayed.id, second.id);
    check events.close();

    http:Response reused = check browser->get(string `/stream?ticket=${ticket.ticket}`);
    test:assertEquals(reused.statusCode, 401);
}
