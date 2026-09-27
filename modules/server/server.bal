import ballerina/http;
import ballerina/log;
import ballerina/task;
import ballerinax/java.jdbc;
import commons/service_commons;
import commons/service_commons.auth as sauth;
import commons/service_commons.db as sdb;
import commons/service_commons.sse;

listener http:Listener notificationListener = new (port);

final jdbc:Client dbClient = check sdb:connect(db);
final Store store = new (dbClient, ns, tablePrefix);
final sauth:Authenticator authenticator = check new (auth);
final sauth:TicketStore tickets = new (ticketTtlSeconds);
final sse:Hub hub = new;

function init() returns error? {
    check sdb:validatePrefix(tablePrefix);
    if db.initSchema {
        check sdb:migrate(dbClient, db.dbType, tablePrefix, migrations);
    }
    check notificationListener.attach(notificationService, basePath);
    _ = check task:scheduleJobRecurByFrequency(new PurgeJob(), purgeIntervalSeconds);
    log:printInfo(string `Notification service on port ${port} at ${basePath} (ns ${ns}, ${db.dbType})`);
}

isolated class PurgeJob {
    *task:Job;

    public isolated function execute() {
        int|error purged = store.purge(service_commons:nowMillis() - retentionDays * 24 * 60 * 60 * 1000);
        if purged is error {
            log:printError("Notification purge failed", purged);
        } else if purged > 0 {
            log:printInfo(string `Purged ${purged} notifications`);
        }
    }
}
