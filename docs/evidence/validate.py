"""Check the linked library and its reviewed release boundary without network access."""

import json
import re
from collections import Counter
from pathlib import Path
from urllib.parse import urlparse


def load(name):
    return json.loads((Path(__file__).parent / name).read_text(encoding="utf-8"))


def unique_keys(rows, key):
    identifiers = [row[key] for row in rows if row.get(key)]
    assert len(identifiers) == len(set(identifiers)), f"Duplicate values for {key}"
    return set(identifiers)


def validate():
    sources = load("sources.json")["sources"]
    claims = load("claims.json")["claims"]
    rules = load("rules.json")["rules"]
    search = load("search_log.json")
    source_ids = unique_keys(sources, "id")
    unique_keys(sources, "doi")
    unique_keys(sources, "pmid")
    claim_ids = unique_keys(claims, "id")
    unique_keys(rules, "id")
    supplied = {
        f"{prefix}{number:02}"
        for prefix, count in [("XC", 22), ("M", 18), ("LA", 7)]
        for number in range(1, count + 1)
    }
    assert supplied <= source_ids
    assert {claim["source_id"] for claim in claims} == source_ids
    by_id = {claim["id"]: claim for claim in claims}
    for source in sources:
        assert source["authors"] and source["title"] and source["journal"]
        assert source["issue_year"] or source["online_year"]
        assert re.fullmatch(r"10\.\d{4,9}/.+", source["doi"], re.IGNORECASE)
        assert by_id[source["primary_claim_id"]]["source_id"] == source["id"]
        assert all(urlparse(url).scheme == "https" for url in source["primary_urls"])
        claim = by_id[source["primary_claim_id"]]
        assert (source["status"] == "full_text_read") == (claim["status"] == "full_text_extracted")
        if source["status"] == "full_text_read":
            audit = source["full_text_audit"]
            assert source["full_text_review"] == "read_and_extracted"
            assert audit["url"] in source["primary_urls"] and audit["pages"] > 0
            assert re.fullmatch(r"[0-9a-f]{64}", audit["sha256"])
            assert (Path(__file__).parent / audit["record"]).is_file()
            assert claim["primary_url"] == audit["url"] and claim["audit_detail"] == audit["record"]
        if source["cohort_overlap"]["status"] == "possible":
            assert source["cohort_overlap"]["other_source"] in source_ids
    for claim in claims:
        assert all(claim[key] for key in (
            "finding", "limitations", "scope", "locator", "tags", "target", "version",
        ))
        if claim["prescription_approved"]:
            assert claim["independent_expert_review"]
    for rule in rules:
        assert set(rule["claim_ids"]) <= claim_ids
        assert rule["claim_ids"] and rule["exclusions"] and rule["test_specification"]
        if rule["can_drive_training"]:
            assert rule["release_status"] == "released" and rule["reviewer"]
            assert rule["implementation_test_status"] == "passed"
            assert all(by_id[c]["prescription_approved"] for c in rule["claim_ids"])
        else:
            assert rule["release_status"] != "released"
    decisions = Counter(
        record["title_screening"]
        for query in search["searches"]
        for record in query["records"]
    )
    assert decisions == search["title_screening_counts"]
    assert sum(decisions.values()) == search["title_records"]
    return f"{len(sources)} sources, {len(claims)} claims, {len(rules)} rule candidates, {sum(decisions.values())} search records"


if __name__ == "__main__":
    print(validate())
