// The provider issues historical deliveries asynchronously to the existing
// webhook. An accepted range is never evidence that a workout was delivered.
const feeds = {
  activities: "ACTIVITY_EXPORT", dailies: "HEALTH_EXPORT",
  sleeps: "HEALTH_EXPORT", hrv: "HEALTH_EXPORT", activityDetails: "ACTIVITY_EXPORT",
  stressDetails: "HEALTH_EXPORT", bodyComps: "HEALTH_EXPORT", pulseOx: "HEALTH_EXPORT",
  hydration: "HEALTH_EXPORT", respiration: "HEALTH_EXPORT", bloodPressures: "HEALTH_EXPORT",
  userMetrics: "HEALTH_EXPORT", healthSnapshot: "HEALTH_EXPORT", skinTemp: "HEALTH_EXPORT",
  epochs: "HEALTH_EXPORT", moveiq: "ACTIVITY_EXPORT", mct: "MCT_EXPORT",
};
const day = 86400;
export class XcHistory {
  constructor(db) {
    this.db = db;
    db.exec(`CREATE TABLE IF NOT EXISTS xc_history (
      owner TEXT NOT NULL REFERENCES subscription(owner) ON DELETE CASCADE,
      feed TEXT NOT NULL, until_s INTEGER NOT NULL, state TEXT NOT NULL,
      retry_s INTEGER NOT NULL DEFAULT 0, code INTEGER, reason TEXT, first_s INTEGER NOT NULL,
      PRIMARY KEY(owner,feed))`);
  }
  enroll(owner, permissions, cycle, now) {
    this.db.prepare("DELETE FROM xc_history WHERE owner=? AND feed IN ('pulseox','allDayRespiration')").run(owner);
    for (const [feed, grant] of Object.entries(feeds)) {
      if (!permissions.includes(grant) || (feed === "mct" && !cycle)) {
        this.db.prepare("DELETE FROM xc_history WHERE owner=? AND feed=?").run(owner,feed);
      } else {
        this.db.prepare("INSERT OR IGNORE INTO xc_history(owner,feed,until_s,state,first_s) VALUES(?,?,?,'pending',?)")
          .run(owner,feed,now,now);
      }
    }
  }
  status(owner) {
    return this.db.prepare("SELECT feed,state,code,reason,until_s,first_s FROM xc_history WHERE owner=? ORDER BY rowid").all(owner);
  }
  next(now) {
    return this.db.prepare("SELECT * FROM xc_history WHERE state IN ('pending','waiting') AND retry_s<=? ORDER BY retry_s,rowid LIMIT 1").get(now);
  }
  async step(job, now, request) {
    // Use one week first for the latest workout, then 30-day windows until
    // Garmin reports the actual entitlement boundary for this feed.
    const start = Math.max(0, job.until_s - (job.first_s === job.until_s ? 7 : 30) * day + 1);
    const response = await request(job.feed, start, job.until_s);
    const code = response.status;
    let reason = null;
    let state = "waiting", cursor = job.until_s, retry = now + 900;
    if (code === 202 || (code === 409 && /duplicate|already (?:requested|processed)/i.test(await response.text()))) {
      state = start === 0 ? "requested" : "pending";
      cursor = start - 1;
      retry = now + 61;
    } else if (code === 403 || code === 400 || code === 404 || code === 422 || code === 412) {
      const detail = (await response.text()).slice(0,4096);
      if (/historical.{0,80}(permission|consent|access)|(?:permission|consent).{0,80}historic|HISTORICAL_DATA_EXPORT/i.test(detail)) reason = "historical_access";
      else if (/enterprise|subscription|starter|license|licence/i.test(detail)) reason = "program_access";
      else if (/not enabled|not configured/i.test(detail)) reason = "endpoint_disabled";
      else if (/permission|consent|scope|not authorized/i.test(detail)) reason = "permission";
      else if (/date|range|too old|past|limit/i.test(detail)) reason = "range";
      state = code === 403 || code === 412 ? "denied" : "unavailable";
    } else if (code === 429) {
      const value = response.headers.get("retry-after");
      const delay = value && /^\d+$/.test(value) ? Number(value) : (Date.parse(value) / 1000 - now);
      retry = now + Math.max(61, Number.isFinite(delay) ? Math.ceil(delay) : 900);
      this.db.prepare("UPDATE xc_history SET retry_s=max(retry_s,?) WHERE state IN ('waiting','pending')").run(retry);
    }
    this.db.prepare("UPDATE xc_history SET state=?,until_s=?,code=?,reason=?,retry_s=? WHERE owner=? AND feed=? AND until_s=? AND first_s=?")
      .run(state,cursor,code,reason,retry,job.owner,job.feed,job.until_s,job.first_s);
  }
}
export function requestHistory(token, feed, start, end) {
  if (!Object.hasOwn(feeds,feed)) throw new Error("Unknown Garmin feed");
  const url = new URL("https://apis.garmin.com/wellness-api/rest/backfill/" + feed);
  url.searchParams.set("summaryStartTimeInSeconds",String(start));
  url.searchParams.set("summaryEndTimeInSeconds",String(end));
  return fetch(url, {redirect:"error", headers:{Authorization:`Bearer ${token.access_token}`}, signal:AbortSignal.timeout(30000)});
}
