# `<commons-notification-bell>`

A round bell button with the caller's unread notification count, kept live. The count covers the caller's
personal notifications and those sent to any of their roles. Use it in a header or top bar, and open your
notifications panel or page when it is clicked. It shows no list itself; pair it with
[`<commons-inbox>`](commons-inbox.md).

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/notification-ui@0.1/dist/notification-ui.bundle.js"></script>

<commons-notification-bell base-url="/api/notifications"></commons-notification-bell>
```

Authentication, installing and theming are covered in the
[guide](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md).

## Attributes and properties

| Property | Attribute | Type | Default | Meaning |
|---|---|---|---|---|
| `baseUrl` | `base-url` | `string` | `""` | Notification service base URL, e.g. `/api/notifications` or `http://localhost:9100/notifications/v1`. Required; nothing loads until it is set |
| `label` | `label` | `string` | `"Notifications"` | Accessible name of the button. The unread count is appended: "Notifications, 3 unread" |
| `auth` | property only | `AuthAdapter` | the `configureAuth` default | Auth adapter for this element's requests |

## Events

| Event | When | `detail` | Bubbles / composed | Cancelable |
|---|---|---|---|---|
| `commons-bell-click` | The button was clicked (mouse, Enter or Space) | none (`null`) | yes / yes | no |

A typical handler opens the inbox:

```js
const bell = document.querySelector("commons-notification-bell");
bell.addEventListener("commons-bell-click", () => {
  document.querySelector("#notifications-panel").toggleAttribute("hidden");
});
```

## Methods

| Method | Returns | What it does |
|---|---|---|
| `refresh()` | `Promise<void>` | Refetches the count from `GET /notifications/unread-count`. On failure it keeps the last count. Rarely needed: the bell already refreshes on every notification event |

## CSS parts

| Part | Element |
|---|---|
| `button` | The 40×40 px round button |
| `badge` | The unread count bubble. Shown only when the count is above zero; above 99 it reads "99+" |

## Slots

None.

## Behavior

### Live updates

The bell subscribes to the shared notification feed for its `base-url` (one SSE stream per URL, shared with any
`<commons-inbox>` on the page). On every event (created, read, unread, read-all, deleted) and after every
reconnect, it refetches the count. It does not compute the count from the events.

The count is `UnreadCount.total` from the service, which counts unread, unexpired notifications addressed to the
caller or to one of the caller's roles.

### Permissions

The service decides. With `enforceScopes` on, the caller's token needs `notification:read` (configurable as
`scopeRead`) for both the count and the stream. If a request fails, the bell keeps its last count (initially 0);
it shows no error.

### States

| State | What shows |
|---|---|
| Before the first response, or on error | The bell with no badge (count 0) or the last known count |
| Count 0 | The bell only |
| Count 1–99 | The badge with the number |
| Count over 99 | The badge with "99+" |

### Accessibility

- A native `<button>`: focusable, and Enter or Space activates it.
- `aria-label` is the `label` plus ", N unread" when there are unread notifications.
- A visible focus ring (`--bc-accent`) on keyboard focus.
- The icon is `aria-hidden`.

## Recipes

### Plain HTML: bell and dropdown inbox

```html
<header>
  <commons-notification-bell id="bell" base-url="/api/notifications"></commons-notification-bell>
</header>
<div id="panel" hidden style="position:absolute; right:16px; width:380px">
  <commons-inbox base-url="/api/notifications"></commons-inbox>
</div>

<script type="module">
  import {bearer, configureAuth} from "https://cdn.jsdelivr.net/npm/@bal-commons/notification-ui@0.1/dist/notification-ui.bundle.js";
  configureAuth(bearer(() => sessionStorage.getItem("token"), () => location.assign("/login")));

  const panel = document.getElementById("panel");
  document.getElementById("bell").addEventListener("commons-bell-click", () => { panel.hidden = !panel.hidden; });
</script>
```

Both elements share one stream, so the bell's count drops as soon as a notification is marked read in the inbox.

### React 19

```tsx
import "@bal-commons/notification-ui";
import {useState} from "react";

export function NotificationsButton() {
  const [open, setOpen] = useState(false);
  return <>
    <commons-notification-bell base-url="/api/notifications" label="Alerts"
        oncommons-bell-click={() => setOpen((o) => !o)} />
    {open && <commons-inbox base-url="/api/notifications" />}
  </>;
}
```

### Styling the badge

```css
commons-notification-bell::part(button) { width: 32px; height: 32px; border: none; }
commons-notification-bell::part(badge) { background: var(--bc-accent); }
```
