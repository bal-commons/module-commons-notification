# @bal-commons/notification-ui

Web Components for the [commons notification service](../README.md): an unread bell and a live inbox. They're
built with Lit and work in any framework (React, Vue, Angular, Svelte) or in plain HTML.

| Element | What it shows |
|---|---|
| `<commons-notification-bell>` | The caller's unread count, kept live |
| `<commons-inbox>` | Personal and role notifications: tabs, read state, "Mark all read", paging, live updates |

The two elements share one live connection per service URL.

## Install

```sh
npm install @bal-commons/notification-ui
```

With no build step, load the single-file bundle from a CDN:

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/notification-ui@0.1/dist/notification-ui.bundle.js"></script>
```

## Use

```html
<commons-notification-bell base-url="/api/notifications"></commons-notification-bell>
<commons-inbox base-url="/api/notifications"></commons-inbox>

<script type="module">
  import {bearer, configureAuth} from "@bal-commons/notification-ui";
  // Every component on the page calls the service with the signed-in user's token.
  configureAuth(bearer(() => sessionStorage.getItem("token"), () => location.assign("/login")));
</script>
```

`base-url` is the service's base path, e.g. `http://localhost:9100/notifications/v1`, or a same-origin proxy path.

React (19+ passes properties and events to custom elements directly):

```tsx
import "@bal-commons/notification-ui";

export function Inbox() {
  return <commons-inbox base-url="/api/notifications"
      oncommons-notification-click={(e) => navigate(e.detail.notification.actionUrl)} />;
}
```

### Authentication

| Adapter | When |
|---|---|
| `bearer(getToken, onUnauthorized?)` | The app has an OIDC or OAuth access token. `getToken` may be async |
| `devUser(userId, roles?, scopes?)` | The service runs without an identity provider and trusts `x-user-*` headers (development only) |
| Your own `{headers(), onUnauthorized?()}` | Anything else, e.g. an API gateway's header |

`configureAuth(adapter)` sets the default for every bal-commons component on the page. To give one element its own
adapter, set its `auth` property: `inbox.auth = bearer(...)`.

## Reference

### `<commons-notification-bell>`

| Attribute | Default | |
|---|---|---|
| `base-url` | | Notification service base URL (required) |
| `label` | `Notifications` | Accessible label |

| Event / method | |
|---|---|
| `commons-bell-click` | The bell was clicked (bubbles, composed) |
| `refresh()` | Refetches the count |

CSS parts: `button`, `badge`.

### `<commons-inbox>`

| Attribute | Default | |
|---|---|---|
| `base-url` | | Notification service base URL (required) |
| `box` | `all` | `all`, `personal` or `role` |
| `page-size` | `20` | Notifications per page |
| `hide-tabs` | | Hides the All / Personal / Roles tabs |

| Event / method | |
|---|---|
| `commons-notification-click` | `detail.notification` was clicked. Cancelable; by default it is marked read |
| `reload()` | Refetches the first page |

CSS parts: `header`, `list`, `item`, `mark-all`.

### Theme

Set these on any ancestor, e.g. `:root`. The components follow `prefers-color-scheme` for their defaults.

`--bc-font`, `--bc-fg`, `--bc-muted`, `--bc-bg`, `--bc-surface`, `--bc-border`, `--bc-accent`, `--bc-accent-soft`,
`--bc-info`, `--bc-warning`, `--bc-error`, `--bc-success`, `--bc-radius`

### Without the elements

`NotificationClient(baseUrl, auth?)` gives typed calls: `list`, `unreadCount`, `markRead`, `markUnread`,
`markAllRead`. The package also exports the TypeScript types (`Notification`, `UnreadCount`, …).

The full API is also described in `dist/custom-elements.json`, the standard manifest that IDEs and tools read.

## What the service side needs

- **CORS**, if the page and the service are on different origins: `corsAllowOrigins` in the service's
  `Config.toml`.
- **A proxy that doesn't buffer SSE.** The elements keep a `text/event-stream` connection open. For nginx:
  `proxy_buffering off; proxy_read_timeout 1h; proxy_http_version 1.1; proxy_set_header Connection "";`
- **The read scope** (`notification:read`) on the user's token, if the service enforces scopes.

## Integration prompt

Copy this into your coding assistant, replacing the bracketed parts:

```text
Add in-app notifications to [my app] using the npm package @bal-commons/notification-ui (Lit Web Components;
API: node_modules/@bal-commons/notification-ui/dist/custom-elements.json and its README).

- The notification service is at [base URL, e.g. /api/notifications, proxied to
  http://notifications:9100/notifications/v1]. If proxied, turn off response buffering for /stream (SSE).
- Authentication: call configureAuth(bearer(getToken, onUnauthorized)) once at startup, where getToken returns
  [how my app gets the signed-in user's access token] and onUnauthorized [what my app does on a 401].
- Put <commons-notification-bell base-url="..."> in [the header / top bar]. On its commons-bell-click event,
  [open a panel / navigate to the notifications page].
- Show <commons-inbox base-url="..."> in [that panel / page]. On commons-notification-click, navigate to
  event.detail.notification.actionUrl when it is set (keep the default behaviour, which marks it read).
- Match the app's design by setting the --bc-* CSS custom properties on :root: accent [colour], font [font],
  radius [px]; keep dark mode working.
- Do not re-implement notification fetching or polling; the components keep themselves live.
```

## Develop

```sh
npm install
npm run build          # dist/index.js (for bundlers), dist/notification-ui.bundle.js (single file), types, manifest
python3 -m http.server 5180   # then open http://localhost:5180/demo/ with the service running on :9100
```
