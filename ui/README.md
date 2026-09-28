# @bal-commons/notification-ui

Web Components for the [commons notification service](../README.md). They're built with Lit and work in any
framework (React, Vue, Angular, Svelte) or in plain HTML.

| Element | What it shows |
|---|---|
| [`<commons-notification-bell>`](docs/commons-notification-bell.md) | The caller's unread count, kept live |
| [`<commons-inbox>`](docs/commons-inbox.md) | Personal and role notifications: tabs, unread and severity filters, `correlationId` filter, read state, "Mark all read", paging, live updates |

The two elements share one live connection per service URL. Installing, authentication, the live model, proxies,
theming, events and framework notes are in the
[guide](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md). For
notifications, chats and files on one page, see
[`<commons-hub>`](https://github.com/bal-commons/commons-hub-ui).

## Install

```sh
npm install @bal-commons/notification-ui
```

With no build step, load the single-file bundle from a CDN:

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/notification-ui@0.1/dist/notification-ui.bundle.js"></script>
```

> The package is not yet published to npm, so the two lines above don't work yet. Until it is, build it locally:
> `npm install && npm run build` here (after building `@bal-commons/ui-core` in `service-commons/ui`), then either
> `npm link` it into your app or copy `dist/notification-ui.bundle.js` into your static files.

## Use

```html
<commons-notification-bell base-url="/api/notifications"></commons-notification-bell>
<commons-inbox base-url="/api/notifications" show-filters></commons-inbox>

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

Each element has a full reference page: attributes, events and `detail` shapes, methods, CSS parts, slots, live
behaviour, permissions and recipes.

- [`<commons-notification-bell>`](docs/commons-notification-bell.md): `base-url`, `label`; event
  `commons-bell-click`; method `refresh()`; parts `button`, `badge`.
- [`<commons-inbox>`](docs/commons-inbox.md): `base-url`, `box`, `page-size`, `hide-tabs`, `unread-only`, `severity`,
  `correlation-id`, `show-filters`; event `commons-notification-click` (cancelable: by default it marks the
  notification read); method `reload()`; parts `header`, `filters`, `mark-all`, `list`, `item`, `empty`; slot
  `empty`.

### Theme

Set the `--bc-*` custom properties on any ancestor, e.g. `:root`. The components follow `prefers-color-scheme` for
their defaults. See [theming](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md#theming).

`--bc-font`, `--bc-fg`, `--bc-muted`, `--bc-bg`, `--bc-surface`, `--bc-border`, `--bc-accent`, `--bc-accent-soft`,
`--bc-info`, `--bc-warning`, `--bc-error`, `--bc-success`, `--bc-radius`

### Without the elements

`NotificationClient(baseUrl, auth?)` gives typed calls: `list`, `unreadCount`, `markRead`, `markUnread`,
`markAllRead`. `notificationFeed(baseUrl, auth?)` gives the shared live feed. The package also exports the
TypeScript types (`Notification`, `UnreadCount`, …).

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
API: node_modules/@bal-commons/notification-ui/dist/custom-elements.json, its README and docs/).

- The notification service is at [base URL, e.g. /api/notifications, proxied to
  http://notifications:9100/notifications/v1]. If proxied, turn off response buffering for /stream (SSE).
- Authentication: call configureAuth(bearer(getToken, onUnauthorized)) once at startup, where getToken returns
  [how my app gets the signed-in user's access token] and onUnauthorized [what my app does on a 401].
- Put <commons-notification-bell base-url="..."> in [the header / top bar]. On its commons-bell-click event,
  [open a panel / navigate to the notifications page].
- Show <commons-inbox base-url="..." show-filters> in [that panel / page]. On commons-notification-click,
  navigate to event.detail.notification.actionUrl when it is set (keep the default behaviour, which marks it
  read). Customise the empty state with a slot="empty" child.
- On [detail pages of my business objects], show <commons-inbox base-url="..." correlation-id="[the object's
  ID]" hide-tabs> for the notifications about that object.
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
