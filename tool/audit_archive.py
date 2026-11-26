"""Compare a GIULIA source and a freshly redacted XC snapshot without writing either.

Usage: python3 tool/audit_archive.py /path/giulia.db /path/redacted.db
Only aggregate counts, date ranges and measurements are written to stdout.
"""
import itertools
import mmap
import json
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def connect(path):
    db = sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True)
    db.execute('PRAGMA query_only=ON')
    db.execute('BEGIN')
    return db


def tables(db):
    return [r[0] for r in db.execute(
        "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]


def expected(name, columns):
    q = [quote(c) for c in columns]
    predicate = ''
    if name == 'app_state':
        predicate = """ WHERE
            (key='app.language' AND value IN ('de','en','it','fr'))
            OR (key='repair.lactate_scout.v14' AND value='done')
            OR (key='training.active_athlete' AND value IN (SELECT id FROM athlete))
            OR (key IN (SELECT 'profile.'||id||'.reference_w' FROM athlete)
                AND length(value) BETWEEN 1 AND 4 AND value NOT GLOB '*[^0-9]*')"""
    elif name == 'sync_outbox':
        predicate = ' WHERE 0'
    elif name == 'strava_sync_state':
        for idx, field in enumerate(columns):
            if field in {'api_base_url', 'session_id', 'session_secret', 'access_token', 'refresh_token'}:
                q[idx] = "''"
            elif field == 'last_error':
                q[idx] = 'NULL'
    return ','.join(q), predicate


def expected_private_settings(db):
    import math
    import re
    from datetime import datetime
    owners = ('own-athlete', 'karina-puercher')
    values = {key:(value,ts) for key,value,ts in db.execute('SELECT key,value,updated_at_utc_us FROM app_state')}
    result = {}
    def get(owner,original,kind):
        raw = values.get(original) or values.get(f'xc.legacy.giulia.{owner}.{kind}')
        if not raw:
            return None,None
        try:
            return json.loads(raw[0]),raw[1]
        except ValueError:
            return None,None
    def add(owner,kind,value,timestamp):
        result[f'xc.legacy.giulia.{owner}.{kind}'] = (value,timestamp)
    def numeric(x):
        return type(x) in (int,float) and math.isfinite(x)
    def samples(v):
        return type(v) is list and all(type(p) is list and len(p)==4 and
            all(n is None or numeric(n) for n in p) for p in v)
    seen = {}
    groups = {}
    for owner in owners:
        rides,stamp = get(owner,'indoor_rides.'+owner,'indoor_rides')
        groups[owner] = (rides if isinstance(rides,list) else [],stamp)
        for item in groups[owner][0]:
            rid=item.get('id','') if isinstance(item,dict) else ''
            if isinstance(rid,str) and re.fullmatch(r'ride-\d{10,20}',rid):
                seen[rid] = 1+seen.get(rid,0)
    for owner in owners:
        item,stamp = get(owner,'weekly_goal.'+owner,'weekly_goal')
        if isinstance(item,dict) and item.get('type') in ('sessions','minutes','kilometres') and numeric(item.get('target')) and item['target']>0:
            add(owner,'weekly_goal',{k:item[k] for k in ('type','target')},stamp)
        item,stamp = get(owner,'profile.'+owner+'.estimate','estimate')
        if isinstance(item,dict) and all(numeric(item.get(k)) for k in ('watt','best_w','window_s','started_us')) and isinstance(item.get('session'),str):
            same = db.execute("""SELECT count(*) FROM session s JOIN normalized_session_record n
                ON s.id=n.source_id AND s.athlete_id=n.athlete_id WHERE s.athlete_id=? AND s.id=? AND n.source='ercolina'""",(owner,item['session'])).fetchone()[0]
            if same:
                add(owner,'estimate',{k:item[k] for k in ('watt','best_w','window_s','started_us','session')},stamp)
        kept = []
        for ride in groups[owner][0]:
            if not isinstance(ride,dict) or seen.get(ride.get('id'))!=1:
                continue
            rid=ride['id']
            start=ride.get('s')
            if not isinstance(start,str) or not start.endswith('Z'):
                continue
            try:
                datetime.fromisoformat(start[:-1]+'+00:00')
            except ValueError:
                continue
            if not (all(numeric(ride.get(k)) for k in ('d','m','kj')) and samples(ride.get('p'))
                and isinstance(ride.get('l'),list) and all(type(n) is int for n in ride['l'])):
                continue
            selected = {k:ride[k] for k in ('id','s','p','l')}
            selected.update({k:ride[k] for k in ('d','e','kj','m','aw','mw','ac','ah','mh','np') if numeric(ride.get(k))})
            kept.append(selected)
            vals,stamp = get(owner,'indoor_ride.samples.'+rid,'indoor_samples.'+rid)
            if samples(vals):
                add(owner,'indoor_samples.'+rid,vals,stamp)
        if kept:
            add(owner,'indoor_rides',kept,groups[owner][1])
    return result


def verify_no_source_credentials(source_db, destination):
    # Known credential columns and namespaces only. Never emit values, digests
    # or substrings. Short IDs/PINs are not reliable byte-search indicators.
    candidates = set()
    def extract(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if any(part in str(key).lower() for part in ('secret','token','key','password','credential')):
                    extract(child)
        elif isinstance(value, str) and len(value) >= 16:
            candidates.add(value.encode('utf-8'))

    for row in source_db.execute('SELECT session_secret,access_token,refresh_token FROM strava_sync_state'):
        for value in row:
            extract(value)
    for value, in source_db.execute(
        "SELECT value FROM app_state WHERE key LIKE 'giulia.device_key.%' OR key LIKE 'giulia.cloud.installation.%'"
    ):
        try:
            extract(json.loads(value))
        except (ValueError, TypeError):
            extract(value)
    checked = []
    for suffix in ('', '-wal', '-journal'):
        file = Path(str(destination) + suffix)
        if not file.exists() or not file.stat().st_size:
            continue
        with file.open('rb') as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as pages:
            if any(pages.find(value) >= 0 for value in candidates):
                raise RuntimeError('A credential indicator was found in published archive pages')
        checked.append(suffix or 'database')
    return {'distinct_indicators_at_least_16_bytes':len(candidates), 'files_with_bytes_checked':checked, 'matches':0}


def report(source, destination):
    started = time.monotonic()
    left, right = connect(source), connect(destination)
    answer = {'utc': datetime.now(timezone.utc).isoformat(), 'source_bytes': source.stat().st_size,
              'copy_bytes': destination.stat().st_size, 'source_mtime_ns': source.stat().st_mtime_ns,
              'schema_version': left.execute('PRAGMA user_version').fetchone()[0], 'tables': {}}
    if tables(left) != tables(right):
        raise RuntimeError('Schema tables differ')
    for table in tables(left):
        info = list(left.execute('PRAGMA table_info(' + quote(table) + ')'))
        cols = [r[1] for r in info]
        pks = [r[1] for r in sorted(info, key=lambda row: row[5]) if r[5]]
        order = ' ORDER BY ' + (','.join(map(quote, pks)) if pks else 'rowid')
        select, predicate = expected(table, cols)
        from_table = ' FROM ' + quote(table)
        l = left.execute('SELECT ' + select + from_table + predicate + order)
        right_filter = " WHERE key NOT LIKE 'xc.legacy.giulia.%'" if table == 'app_state' else ''
        r = right.execute('SELECT ' + ','.join(map(quote, cols)) + from_table + right_filter + order)
        count = 0
        for a, b in itertools.zip_longest(l, r):
            if a != b:
                raise RuntimeError('Row mismatch in ' + table + ' at ordinal ' + str(count + 1))
            count += 1
        if table == 'app_state':
            expected_legacy = expected_private_settings(left)
            actual_legacy = {k:(json.loads(v),ts) for k,v,ts in right.execute(
                "SELECT key,value,updated_at_utc_us FROM app_state WHERE key LIKE 'xc.legacy.giulia.%'")}
            if expected_legacy != actual_legacy:
                raise RuntimeError('Independent athlete-scoped training fields differ')
            count += len(actual_legacy)
            answer['typed_private_training_rows'] = len(actual_legacy)
        total = count if table not in ('sync_outbox', 'app_state') else left.execute('SELECT count(*)' + from_table).fetchone()[0]
        answer['tables'][table] = {'source': total, 'equal_after_redaction': count}
    answer['integrity'] = right.execute('PRAGMA quick_check').fetchall()
    answer['invalid_foreign_keys'] = len(right.execute('PRAGMA foreign_key_check').fetchall())
    query = """SELECT CASE a.id WHEN 'own-athlete' THEN 'Jan' WHEN 'karina-puercher' THEN 'Karina' ELSE 'weiteres Profil' END,n.source,count(*),sum(n.duration_seconds),sum(n.moving_time_seconds),
        date(min(n.started_at_utc_us)/1000000,'unixepoch'),date(max(n.started_at_utc_us)/1000000,'unixepoch')
        FROM normalized_session_record n JOIN athlete a ON a.id=n.athlete_id
        GROUP BY a.name,n.source ORDER BY a.name,n.source"""
    stats = list(right.execute(query))
    if stats != list(left.execute(query)):
        raise RuntimeError('Aggregate mismatch')
    answer['normalized_by_profile'] = [dict(zip(('athlete','source','sessions','duration_s','moving_s','first_utc','last_utc'), row)) for row in stats]
    answer['profile_counts'] = {}
    for t in ['session','performance_test','lactate_sample','observation','training_zone_set','training_goal','planned_workout','athlete_check_in','female_athlete_profile','cycle_period_record','daily_cycle_symptom_record','coach_decision_record']:
        query = ("""SELECT CASE a.id WHEN 'own-athlete' THEN 'Jan' WHEN 'karina-puercher' THEN 'Karina' ELSE 'weiteres Profil' END,count(t.athlete_id) FROM athlete a LEFT JOIN """ + quote(t)
                 + ' t ON a.id=t.athlete_id GROUP BY a.id,a.name ORDER BY a.name')
        lv, rv = list(left.execute(query)), list(right.execute(query))
        if lv != rv:
            raise RuntimeError('Athlete count mismatch in ' + t)
        answer['profile_counts'][t] = dict(rv)
    answer['rows_source'] = sum(v['source'] for v in answer['tables'].values())
    answer['rows_copy'] = sum(v['equal_after_redaction'] for v in answer['tables'].values())
    answer['credential_byte_check'] = verify_no_source_credentials(left, destination)
    answer['elapsed_seconds'] = round(time.monotonic()-started,3)
    answer['source_mtime_unchanged'] = answer['source_mtime_ns'] == source.stat().st_mtime_ns
    left.close()
    right.close()
    return answer


if __name__ == '__main__':
    print(json.dumps(report(*map(Path,sys.argv[1:])), indent=2, ensure_ascii=False))
