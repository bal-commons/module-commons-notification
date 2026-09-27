import ballerina/http;
import ballerina/url;

# Client for the notification service.
public isolated client class Client {
    private final http:Client http;
    private final map<string> & readonly headers;

    # Creates a client.
    #
    # + serviceUrl - Base URL including the base path, e.g. `http://localhost:9100/notifications/v1`
    # + config - HTTP client settings, including `auth` for OAuth2 client credentials
    # + headers - Sent on every request, e.g. `x-api-key`, or `x-user-id` in trusted-header mode
    # + return - An error if the client cannot be created
    public isolated function init(string serviceUrl, http:ClientConfiguration config = {}, map<string> headers = {})
            returns error? {
        self.http = check new (serviceUrl, config);
        self.headers = headers.cloneReadOnly();
    }

    # Sends a notification.
    #
    # + notification - The notification
    # + return - The stored notification (the original one on an idempotent retry), or an error
    remote isolated function send(NewNotification notification) returns Notification|error {
        return self.http->post("/notifications", notification, self.headers);
    }

    # Lists the caller's notifications, newest first.
    #
    # + options - Filters and paging
    # + return - One page, or an error
    remote isolated function list(*ListOptions options) returns NotificationPage|error {
        return self.http->get("/notifications" + check queryString(options), self.headers);
    }

    # Gets one of the caller's notifications.
    #
    # + id - Notification ID
    # + return - The notification, or an error (404 when it is not visible to the caller)
    remote isolated function get(string id) returns Notification|error {
        return self.http->get(check itemPath(id), self.headers);
    }

    # Marks a notification read for the caller.
    #
    # + id - Notification ID
    # + return - The notification, or an error
    remote isolated function markRead(string id) returns Notification|error {
        return self.http->put(check itemPath(id) + "/read", (), self.headers);
    }

    # Marks a notification unread for the caller.
    #
    # + id - Notification ID
    # + return - The notification, or an error
    remote isolated function markUnread(string id) returns Notification|error {
        return self.http->delete(check itemPath(id) + "/read", (), self.headers);
    }

    # Marks every matching unread notification read for the caller.
    #
    # + filter - Which notifications to mark
    # + return - How many were marked, or an error
    remote isolated function markAllRead(*ReadAllFilter filter) returns ReadAllResult|error {
        return self.http->post("/notifications/read-all", filter, self.headers);
    }

    # Counts the caller's unread notifications.
    #
    # + return - The counts, or an error
    remote isolated function unreadCount() returns UnreadCount|error {
        return self.http->get("/notifications/unread-count", self.headers);
    }

    # Lists any recipient's notifications. Requires the admin scope.
    #
    # + options - Filters and paging
    # + return - One page, or an error
    remote isolated function adminList(*AdminListOptions options) returns NotificationPage|error {
        return self.http->get("/admin/notifications" + check queryString(options), self.headers);
    }

    # Deletes a notification for every recipient. Requires the admin scope.
    #
    # + id - Notification ID
    # + return - An error if it does not exist or the call fails
    remote isolated function delete(string id) returns error? {
        http:Response response = check self.http->delete(check itemPath(id), (), self.headers);
        if response.statusCode != http:STATUS_NO_CONTENT {
            return error(string `Delete failed with status ${response.statusCode}: ${check response.getTextPayload()}`);
        }
    }

    # Issues a single-use ticket for opening the SSE stream from a browser.
    #
    # + return - The ticket, or an error
    remote isolated function streamTicket() returns StreamTicket|error {
        return self.http->post("/stream-ticket", (), self.headers);
    }

    # Opens the caller's SSE stream.
    #
    # + lastEventId - Replays visible notifications created after this event
    # + return - The event stream, or an error
    remote isolated function events(string? lastEventId = ()) returns stream<http:SseEvent, error?>|error {
        map<string> headers = {...self.headers};
        if lastEventId is string {
            headers["Last-Event-ID"] = lastEventId;
        }
        return self.http->get("/stream", headers);
    }
}

isolated function itemPath(string id) returns string|error =>
    string `/notifications/${check url:encode(id, "UTF-8")}`;

isolated function queryString(record {} params) returns string|error {
    string[] parts = [];
    foreach [string, anydata] [key, value] in params.entries() {
        if value !is () {
            parts.push(string `${key}=${check url:encode(value.toString(), "UTF-8")}`);
        }
    }
    return parts.length() == 0 ? "" : "?" + string:'join("&", ...parts);
}
