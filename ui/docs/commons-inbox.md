# `<commons-inbox>`

The caller's notifications, newest first and kept live: personal ones and those sent to their roles. Each row
shows the title, body, whether it is personal or for a role, the time, and a read/unread toggle. The header has
All / Personal / Roles tabs, optional unread and severity filters, and "Mark all read". Use it as a notifications
page, a dropdown under [`<commons-notification-bell>`](commons-notification-bell.md), or, with `correlation-id`,
as "the notifications about this order" on a detail page.

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/notification-ui@0.1/dist/notification-ui.bundle.js"></script>

<commons-inbox base-url="/api/notifications"></commons-inbox>
```

Authentication, installing and theming are covered in the
[guide](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md).

## Attributes and properties

| Property | Attribute | Type | Default | Meaning |
|---|---|---|---|---|
| `baseUrl` | `base-url` | `string` | `""` | Notification service base URL. Required; nothing loads until it is set |
| `box` | `box` (reflected) | `"all" \| "personal" \| "role"` | `"all"` | Which box to list. The tabs change it |
| `pageSize` | `page-size` | `number` | `20` | Notifications per page (the service caps it at `maxPageSize`, 100 by default) |
| `hideTabs` | `hide-tabs` | `boolean` | `false` | Hides the All / Personal / Roles tabs |
| `unreadOnly` | `unread-only` (reflected) | `boolean` | `false` | Lists only unread notifications |
| `severity` | `severity` | `"INFO" \| "WARNING" \| "ERROR" \| "SUCCESS"` | unset | Lists only this severity |
| `correlationId` | `correlation-id` | `string` | unset | Lists only notifications about this business object |
| `showFilters` | `show-filters` | `boolean` | `false` | Shows an "Unread" checkbox and a severity drop-down in the header. They set `unreadOnly` and `severity` |
| `auth` | property only | `AuthAdapter` | the `configureAuth` default | Auth adapter for this element's requests |

Changing `box`, `unreadOnly`, `severity` or `correlationId` refetches the first page. Changing `baseUrl` also
switches the live stream.

## Events

| Event | When | `detail` | Bubbles / composed | Cancelable |
|---|---|---|---|---|
| `commons-notification-click` | A row was clicked, or Enter was pressed on a focused row. Not fired by the "Mark read" toggle | `{notification: Notification}` | yes / yes | yes |

Default action: if the notification is unread, it is marked read (`PUT /notifications/{id}/read`). Call
`event.preventDefault()` to leave it unread.

```ts
interface Notification {
  id: string;
  recipientType: "USER" | "ROLE";
  recipientId: string;
  severity: "INFO" | "WARNING" | "ERROR" | "SUCCESS";
  category?: string;
  title: string;
  body?: string;
  actionUrl?: string;
  correlationId?: string;
  sender?: string;
  payload?: unknown;
  createdAt: string;
  expiresAt?: string;
  read?: boolean;
  readAt?: string;
}
```

The inbox does not follow `actionUrl` itself. A typical handler does:

```js
inbox.addEventListener("commons-notification-click", (event) => {
  const {actionUrl} = event.detail.notification;
  if (actionUrl) {
    router.navigate(actionUrl);   // the notification is still marked read
  }
});
```

## Methods

| Method | Returns | What it does |
|---|---|---|
| `reload()` | `Promise<void>` | Refetches the first page with the current filters |

## CSS parts

| Part | Element |
|---|---|
| `header` | The header row: tabs, filters and "Mark all read" |
| `filters` | The unread and severity filters (only with `show-filters`) |
| `mark-all` | The "Mark all read" button |
| `list` | The `<ul>` of notifications |
| `item` | One notification row. Its class is its severity (`INFO`, `WARNING`, …) plus `read` when read |
| `empty` | The empty state |

## Slots

| Slot | Replaces |
|---|---|
| `empty` | The "No notifications." text |

```html
<commons-inbox base-url="/api/notifications" unread-only>
  <p slot="empty">You're all caught up.</p>
</commons-inbox>
```

## Behavior

### Live updates

The inbox subscribes to the shared notification feed for its `base-url`. The stream replays missed
`notification.created` events after a reconnect.

| Stream event | What the inbox does |
|---|---|
| `notification.created` | Inserts it at the top if it matches the current box, severity and `correlationId` and is not already shown |
| `notification.read` / `notification.unread` | Updates that row's read state. With `unread-only`, a read row is removed |
| `notification.deleted` | Removes the row |
| `notification.read-all`, reconnect | Refetches the first page |

Read-state events go to the user who changed the state, so marking a notification read in one tab updates the
caller's other tabs.

### What the service decides

- The service lists only the caller's personal notifications and those sent to one of their roles, and hides
  expired ones. Read state is per user, also for role notifications.
- With `enforceScopes` on, the token needs `notification:read`.
- "Mark all read" marks what the filters show. It calls `POST /notifications/read-all` with the current `box` and
  `correlationId`. The service can't filter read-all by severity, so with a `severity` filter the inbox marks the
  loaded unread notifications one by one. The list is then refetched.

### Paging

When the service returns a `nextCursor`, a "Load more" button appears below the list and appends the next page.

### States

| State | What shows |
|---|---|
| Loading | The previous rows, if any. No spinner |
| Empty (loaded, nothing matches) | The `empty` part with the `empty` slot or "No notifications." |
| Error on load | The error message in red (`role="alert"`) above the list |

Errors from "Load more", the read toggle and "Mark all read" show the same way, and clear on the next success.

### Accessibility

- The tabs are buttons with `role="tab"` and `aria-selected` inside a `role="tablist"`. Only the selected tab is in the
  Tab order; Left and Right arrows move between tabs.
- Each row is focusable (`tabindex="0"`); Enter opens it (fires `commons-notification-click`).
- Unread rows have a dot with `aria-label="unread"`; read rows are dimmed.
- The "Mark read" / "Mark unread" toggle in each row is a native button.
- The severity drop-down has `aria-label="Severity"`; the list has `aria-label="Notifications"`.

## Recipes

### Plain HTML: notifications page that follows `actionUrl`

```html
<commons-inbox id="inbox" base-url="/api/notifications" show-filters page-size="30">
  <p slot="empty">No notifications yet.</p>
</commons-inbox>

<script type="module">
  import {bearer, configureAuth} from "https://cdn.jsdelivr.net/npm/@bal-commons/notification-ui@0.1/dist/notification-ui.bundle.js";
  configureAuth(bearer(() => sessionStorage.getItem("token")));

  document.getElementById("inbox").addEventListener("commons-notification-click", (e) => {
    const url = e.detail.notification.actionUrl;
    if (url) location.assign(url);
  });
</script>
```

### React 19

```tsx
import "@bal-commons/notification-ui";
import type {Notification} from "@bal-commons/notification-ui";
import {useNavigate} from "react-router-dom";

export function Inbox() {
  const navigate = useNavigate();
  return <commons-inbox base-url="/api/notifications" showFilters={true}
      oncommons-notification-click={(e: CustomEvent<{notification: Notification}>) => {
        const {actionUrl} = e.detail.notification;
        if (actionUrl) navigate(actionUrl);
      }} />;
}
```

### Keep a notification unread until the user acts

```js
inbox.addEventListener("commons-notification-click", (e) => {
  if (e.detail.notification.category === "approval") {
    e.preventDefault();                      // stays unread
    openApprovalDialog(e.detail.notification.correlationId);
  }
});
```

### Notifications about one object

```html
<commons-inbox base-url="/api/notifications" correlation-id="order-4711" hide-tabs></commons-inbox>
```

Combine it with `<commons-conversation-list correlation-id="order-4711">` and
`<commons-case-list correlation-id="order-4711">` for a full "order activity" view; see the `correlationId`
convention in the [guide](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md#the-correlationid-convention).
