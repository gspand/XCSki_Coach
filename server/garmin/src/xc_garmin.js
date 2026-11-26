import { createHash, randomUUID } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { encryptJson, decryptJson } from "./token_crypto.js";

// Only known wellness feeds may enter the ordinary health archive. Additional
// Women's Health feeds can use the dedicated, always opt-in webhook.
const wellness = new Set(["dailies", "epochs", "sleeps", "hrv", "stressDetails",
  "bodyComps", "pulseox", "allDayRespiration", "bloodPressures", "healthSnapshot",
  "skinTemp", "userMetrics", "nutrition", "hydration", "breathingVariations"]);
const cycles = /^(mct|menstrual|womenshealth|womenhealth|cycle)/i;
const digest = value => createHash("sha256").update(value).digest("hex");

export class XcGarminInbox {
  constructor(filename, key) {
    this.key = key;
    this.db = new DatabaseSync(filename);
    this.db.exec(`
      PRAGMA foreign_keys=ON;
      PRAGMA synchronous=FULL;
      CREATE TABLE IF NOT EXISTS subscription (
        owner TEXT PRIMARY KEY, subject TEXT NOT NULL, cycle INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS event (
        seq INTEGER PRIMARY KEY, owner TEXT NOT NULL REFERENCES subscription(owner) ON DELETE CASCADE,
        receipt TEXT NOT NULL UNIQUE, fingerprint TEXT NOT NULL, kind TEXT NOT NULL,
        data TEXT NOT NULL, UNIQUE(owner, fingerprint)
      );
      CREATE INDEX IF NOT EXISTS event_by_owner ON event(owner,seq);
    `);
  }
  transaction(fn) {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const result = fn();
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }
  settings(owner, subject) {
    return this.db.prepare("SELECT cycle FROM subscription WHERE owner=? AND subject=?").get(owner, digest(subject));
  }
  enroll(owner, subject, cycle) {
    this.transaction(() => {
      this.db.prepare("DELETE FROM subscription WHERE owner=? AND subject<>?").run(owner, digest(subject));
      this.db.prepare("INSERT INTO subscription VALUES(?,?,?) ON CONFLICT(owner) DO UPDATE SET cycle=excluded.cycle").run(owner, digest(subject), Number(cycle));
      if (!cycle) this.db.prepare("DELETE FROM event WHERE owner=? AND kind='cycle'").run(owner);
    });
  }
  restrict(owner, permissions) {
    const allowed = new Set(permissions);
    const remove = this.db.prepare("DELETE FROM event WHERE owner=? AND kind=?");
    this.transaction(() => {
      if (!allowed.has("MCT_EXPORT")) remove.run(owner, "cycle");
      if (!allowed.has("HEALTH_EXPORT")) remove.run(owner, "health");
      if (!allowed.has("ACTIVITY_EXPORT")) {
        for (const kind of ["activity","file","detail"]) remove.run(owner,kind);
      }
    });
  }
  forget(owner) {
    this.db.prepare("DELETE FROM subscription WHERE owner=?").run(owner);
  }
  put(owner, subject, kind, type, value) {
    const settings = this.settings(owner, subject);
    if (!settings || (kind === "cycle" && !settings.cycle)) return;
    // Garmin's legacy token and one-time file URL must never reach the app.
    const { userId, userAccessToken, accessToken, callbackURL, ...data } = value;
    if (kind === "file") data.callbackURL = callbackURL;
    if (kind === "cycle") {
      delete data.pregnancySnapshot;
      // Garmin MCT supplies the cycle start and a one-based day, not the
      // summary's calendar date. Add the date the existing app indexes.
      if (!data.calendarDate && /^\d{4}-\d{2}-\d{2}$/.test(data.periodStartDate)
          && Number.isSafeInteger(data.dayInCycle) && data.dayInCycle >= 1) {
        const start = new Date(data.periodStartDate + "T00:00:00Z");
        const date = new Date(start.valueOf() + (data.dayInCycle - 1) * 86400000);
        if (Number.isFinite(start.valueOf()) && start.toISOString().startsWith(data.periodStartDate)
            && Number.isFinite(date.valueOf()) && date.getUTCFullYear() <= 9999) {
          data.calendarDate = date.toISOString().slice(0,10);
        }
      }
    }
    const event = { type, data };
    const fingerprint = digest(JSON.stringify([kind, event]));
    this.db.prepare("INSERT OR IGNORE INTO event(owner,receipt,fingerprint,kind,data) VALUES(?,?,?,?,?)").run(
      owner, randomUUID(), fingerprint, kind, JSON.stringify(encryptJson(event, this.key)));
  }
  receive(payload, owners, cycleOnly, normalize, healthEndpoint) {
    this.transaction(() => {
      for (const [type, rows] of Object.entries(payload)) {
        if (!Array.isArray(rows)) continue;
        if (["deregistrations","userPermissionsChange"].includes(type)) continue;
        if (/pregnan/i.test(type)) continue;
        const activity = ["activities","manuallyUpdatedActivities"].includes(type);
        const kind = cycleOnly || cycles.test(type) ? "cycle" : activity ? "activity"
          : type === "activityFiles" ? "file" : ["activityDetails","moveIQActivities"].includes(type) ? "detail" : (wellness.has(type) || healthEndpoint) ? "health" : null;
        if (!kind) continue;
        for (const row of rows) {
          if (typeof row?.userId !== "string" || !row.userId) continue;
          for (const session of owners(row.userId)) {
            const owner = session.owner_user_id;
            if (!this.settings(owner, row.userId)) continue;
            const permission = kind === "cycle" ? "MCT_EXPORT" : kind === "health" ? "HEALTH_EXPORT" : "ACTIVITY_EXPORT";
            if (Array.isArray(session.garmin_permissions) && !session.garmin_permissions.includes(permission)) continue;
            let value = row;
            // Preserve even an incomplete summary as a raw activity detail.
            let recordKind = kind;
            if (kind === "activity") {
              try {
                value = normalize(row);
                if (!value.startedAt || !(value.elapsedTime > 0)) throw new Error();
              } catch { value = row; recordKind = "detail"; }
            }
            if (kind === "file" && !row.callbackURL) continue;
            if (type === "activityDetails" && kind === "detail" && row.summary && row.activityId &&
                (!row.summary.activityId || String(row.summary.activityId) === String(row.activityId))) {
              // A details-only delivery can carry the sole workout summary.
              // Preserve its raw sample series alongside the book entry.
              try {
                const workout = normalize({...row.summary, activityId:row.activityId});
                if (workout.startedAt && workout.elapsedTime > 0) this.put(owner,row.userId,"activity",type,workout);
              } catch { /* Incomplete details still belong in the archive. */ }
            }
            this.put(owner, row.userId, recordKind, type, value);
          }
        }
      }
    });
  }
  page(owner) {
    // Materialize just the sizes first. Holding a native SQLite iterator
    // across JSON decryption allowed its statement to be finalized during GC.
    const rows = this.db.prepare("SELECT seq,receipt,kind,length(data) AS size FROM event WHERE owner=? AND kind<>'file' ORDER BY seq LIMIT 32").all(owner);
    const payload = this.db.prepare("SELECT data FROM event WHERE seq=? AND owner=?");
    const result = [];
    let bytes = 0;
    for (const row of rows) {
      if (result.length && bytes + row.size > 2000000) break;
      const data = payload.get(row.seq,owner).data;
      result.push({ receipt: row.receipt, kind: row.kind, ...decryptJson(JSON.parse(data), this.key) });
      bytes += row.size;
    }
    return result;
  }
  ack(owner, receipts) {
    const del = this.db.prepare("DELETE FROM event WHERE owner=? AND receipt=? AND kind<>'file'");
    this.transaction(() => { for (const id of receipts) del.run(owner, id); });
  }
  files() {
    return this.db.prepare("SELECT owner,receipt,data FROM event WHERE kind='file' ORDER BY seq").all()
      .map(row => ({...row, data: decryptJson(JSON.parse(row.data),this.key).data}));
  }
  finishFile(owner, receipt, subject, activity) {
    this.transaction(() => {
      const removed = this.db.prepare("DELETE FROM event WHERE owner=? AND receipt=? AND kind='file'").run(owner,receipt);
      if (removed.changes) this.put(owner,subject,"activity","activityFiles",activity);
    });
  }
}
