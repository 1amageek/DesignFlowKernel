#!/usr/bin/env python3
"""Generate a deterministic one-entry retention history for CI smoke tests."""

import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate-retention-fixture.py <project-root> <run-id>")

    project_root = Path(sys.argv[1]).resolve()
    run_id = sys.argv[2]
    retention_directory = project_root / ".xcircuite" / "runs" / run_id / "retention"
    retention_directory.mkdir(parents=True, exist_ok=True)

    dashboard = {"runID": run_id, "source": "retained-corpus-ci"}
    (retention_directory / "dashboard.json").write_text(
        json.dumps(dashboard, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )

    recorded_at = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    material = {
        "entryID": "entry-1",
        "qualificationDigest": "c" * 64,
        "recordedAt": recorded_at,
        "runID": run_id,
        "sequence": 1,
    }
    canonical = json.dumps(material, sort_keys=True, separators=(",", ":")).encode("utf-8")
    entry = dict(material)
    entry["entrySHA256"] = hashlib.sha256(canonical).hexdigest()
    (retention_directory / "history.jsonl").write_text(
        json.dumps(entry, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
