import commons/service_commons.auth as sauth;
import commons/service_commons.db as sdb;

# Port of the service's listener.
configurable int port = 9100;
# Base path the service is attached at.
configurable string basePath = "/notifications/v1";
# Namespace of every notification this instance stores and serves.
configurable string ns = "default";
# Prefix of the service's tables.
configurable string tablePrefix = "notification_";
# Listener auth.
configurable sauth:AuthConfig auth = {};
# Database connection.
configurable sdb:DbConfig db = {};
# Scope required to send notifications.
configurable string scopeSend = "notification:send";
# Scope required to read and mark the caller's own notifications.
configurable string scopeRead = "notification:read";
# Scope required to list any recipient's notifications and to delete.
configurable string scopeAdmin = "notification:admin";
# Notifications older than this are purged, read or not.
configurable int retentionDays = 90;
# How often the purge job runs, in seconds.
configurable decimal purgeIntervalSeconds = 3600;
# Largest page a listing returns.
configurable int maxPageSize = 100;
# Most notifications replayed when a stream reconnects with `Last-Event-ID`.
configurable int replayLimit = 200;
# Lifetime of an SSE stream ticket, in seconds.
configurable int ticketTtlSeconds = 60;
# Origins allowed by CORS.
configurable string[] corsAllowOrigins = ["*"];
