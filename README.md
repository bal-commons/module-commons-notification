# commons/notification

Role and personal notification inboxes with per-user read state and real-time delivery over SSE.

| Module | Contents |
|---|---|
| `notification` | Types and `Client`. Safe to import anywhere. |
| `notification.server` | The HTTP service. Importing it starts the listener. |

## UI components

[`@bal-commons/notification-ui`](ui/README.md) (npm) provides `<commons-notification-bell>` and `<commons-inbox>`,
live Web Components for this service, and an integration prompt to copy into a coding assistant.

## Run it inside an application

```ballerina
import ballerinax/h2.driver as _;              // or mysql.driver / postgresql.driver
import commons/notification.server as _;
```

```toml
# Config.toml
[commons.notification.server]
port = 9100                      # default
basePath = "/notifications/v1"   # default
ns = "my-app"

[commons.notification.server.auth]
enableJwtAuth = true
jwksUrl = "https://idp.example.com/oauth2/jwks"
rolesClaim = "groups"            # default
enforceScopes = true

[commons.notification.server.db]
dbType = "POSTGRESQL"
url = "jdbc:postgresql://localhost:5432/myapp"
user = "app"
password = "app"
```

Other settings (see `modules/server/config.bal`): `tablePrefix`, scope names, `retentionDays` (90), `purgeIntervalSeconds`,
`maxPageSize`, `replayLimit`, `ticketTtlSeconds`, `corsAllowOrigins`.

With neither JWT nor API key enabled, the service trusts `x-user-id`, `x-user-roles` (comma-separated) and
`x-user-scopes` headers. That is for local development only.

## Visibility

A notification goes to one user (`USER`) or to a role (`ROLE`). A role notification is stored once. Who sees it is
decided when it is read, from the roles in the reader's token, so the service never needs role membership.
Read state is per user: marking a role notification read affects only the caller.

## API

| Method | Path | Scope | |
|---|---|---|---|
| `POST` | `/notifications` | send | Send. `201`, or `200` with the original when `idempotencyKey` repeats |
| `GET` | `/notifications` | read | Caller's inbox, newest first. `box=all\|personal\|role`, `role`, `severity`, `category`, `correlationId`, `read`, `cursor`, `limit` |
| `GET` | `/notifications/unread-count` | read | `{total, personal, roles: {role: n}}` |
| `GET` | `/notifications/{id}` | read | `404` unless visible to the caller |
| `PUT` | `/notifications/{id}/read` | read | Mark read |
| `DELETE` | `/notifications/{id}/read` | read | Mark unread |
| `POST` | `/notifications/read-all` | read | Mark all read; optional `{box, role, category, correlationId}` |
| `GET` | `/admin/notifications` | admin | Any recipient: `recipientType`, `recipientId`, filters, paging |
| `DELETE` | `/notifications/{id}` | admin | Delete for everyone |
| `POST` | `/stream-ticket` | read | `{ticket, expiresIn}` for a browser `EventSource` |
| `GET` | `/stream` | read | SSE stream |

Scopes default to `notification:send`, `notification:read` and `notification:admin`. API-key callers hold all of them.

## Events

| Event | To | Data |
|---|---|---|
| `notification.created` | Recipient user or everyone in the role | The notification, `read: false` |
| `notification.read` / `notification.unread` | The reader | `{id, readAt?}` |
| `notification.read-all` | The reader | `{count}` |
| `notification.deleted` | Recipients | `{id}` |

The stream opens with a `: connected` comment and sends `: keepalive` every 15 s while idle.

### Browser

`EventSource` cannot send headers and tickets are single-use, so reconnect with a fresh ticket and the last event ID:

```js
let lastId;
async function connect() {
  const { ticket } = await api.post("/stream-ticket");
  const url = `${base}/stream?ticket=${ticket}` + (lastId ? `&lastEventId=${lastId}` : "");
  const es = new EventSource(url);
  es.addEventListener("notification.created", e => { lastId = e.lastEventId; render(JSON.parse(e.data)); });
  es.onerror = () => { es.close(); setTimeout(connect, 3000); };
}
```

Missed notifications, up to `replayLimit`, are replayed before live events. Replay covers `notification.created` only.
After a long gap, refetch `unread-count`.

## From a workflow

```ballerina
final notification:Client notifications = check new ("http://localhost:9100/notifications/v1",
    headers = {"x-api-key": apiKey});

notification:Notification sent = check notifications->send({
    recipientType: notification:ROLE,
    recipientId: "PropertyManager",
    severity: notification:WARNING,
    title: "No contractor reply in 48h",
    correlationId: caseId,
    idempotencyKey: string `${caseId}/escalation`
});
```

Set `idempotencyKey` when sending from an activity, so a retried activity doesn't notify twice.

## Storage

Tables `<prefix>item` and `<prefix>read` (default prefix `notification_`), created by the migration runner on startup.
Timestamps are epoch milliseconds. Notifications older than `retentionDays`, and expired ones, are purged with their
read rows.

Tested on H2. The SQL is kept portable to MySQL and PostgreSQL, but it hasn't been run against them yet.
