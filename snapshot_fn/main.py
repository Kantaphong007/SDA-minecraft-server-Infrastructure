import os
from datetime import datetime, timezone, timedelta
from googleapiclient import discovery
from google.auth import default as google_auth_default


def _utc_now():
    return datetime.now(timezone.utc)


def _parse_rfc3339(ts: str):
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.fromisoformat(ts)


def snapshot(request):
    project_id = os.environ["PROJECT_ID"]
    zone = os.environ["ZONE"]
    disk_name = os.environ["DISK_NAME"]
    retention_minutes = int(os.environ.get("RETENTION_MINUTES", "1440"))  # default 1 day

    managed_label_key = "managed_by"
    managed_label_val = "tf-scheduler"
    disk_label_key = "source_disk"
    disk_label_val = disk_name

    creds, _ = google_auth_default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    compute = discovery.build("compute", "v1", credentials=creds, cache_discovery=False)

    # 1) Create snapshot
    snap_name = f"mc-{disk_name}-{_utc_now().strftime('%Y%m%d-%H%M%S')}".lower()
    body = {
        "name": snap_name,
        "labels": {
            managed_label_key: managed_label_val,
            disk_label_key: disk_label_val,
        },
    }

    op = compute.disks().createSnapshot(
        project=project_id,
        zone=zone,
        disk=disk_name,
        body=body,
    ).execute()

    # 2) Cleanup old snapshots
    cutoff = _utc_now() - timedelta(minutes=retention_minutes)
    flt = f"(labels.{managed_label_key} = {managed_label_val}) AND (labels.{disk_label_key} = {disk_label_val})"

    snaps = []
    req = compute.snapshots().list(project=project_id, filter=flt, maxResults=500)
    while req is not None:
        resp = req.execute()
        snaps.extend(resp.get("items", []))
        req = compute.snapshots().list_next(previous_request=req, previous_response=resp)

    deleted = 0
    for s in snaps:
        ts = s.get("creationTimestamp")
        if not ts:
            continue
        created = _parse_rfc3339(ts)
        if created < cutoff:
            compute.snapshots().delete(project=project_id, snapshot=s["name"]).execute()
            deleted += 1

    return {
        "status": "ok",
        "created_snapshot": snap_name,
        "op": op.get("name"),
        "deleted_old_snapshots": deleted,
        "retention_minutes": retention_minutes,
    }
