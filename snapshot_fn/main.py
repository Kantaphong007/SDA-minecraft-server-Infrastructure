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
    # ZONE เดิมจะกลายเป็นค่า Default เฉพาะกรณีหาไม่เจอจริงๆ
    default_zone = os.environ.get("ZONE", "asia-southeast1-b") 
    pvc_name = os.environ.get("PVC_NAME", "minecraft-pvc")
    retention_minutes = int(os.environ.get("RETENTION_MINUTES", "1440"))

    creds, _ = google_auth_default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    compute = discovery.build("compute", "v1", credentials=creds, cache_discovery=False)

    # --- ส่วนที่แก้ไข: ค้นหา Disk จากทุกโซน (Aggregated List) ---
    found_disk_name = None
    actual_zone = None

    # ดึงรายชื่อดิสก์จากทุกโซนในโปรเจกต์
    request_agg = compute.disks().aggregatedList(project=project_id)
    while request_agg is not None:
        response_agg = request_agg.execute()
        items = response_agg.get('items', {})
        
        for zone_path, data in items.items():
            # zone_path จะมาในรูปแบบ "zones/asia-southeast1-a"
            current_zone = zone_path.split('/')[-1]
            disks = data.get('disks', [])
            
            for disk in disks:
                name = disk.get("name", "")
                description = disk.get("description", "") or ""
                
                # ตรวจสอบชื่อ PVC ใน Description เหมือนเดิม
                if pvc_name in description and name.startswith("pvc-"):
                    found_disk_name = name
                    actual_zone = current_zone
                    break
            if found_disk_name: break
        if found_disk_name: break
        request_agg = compute.disks().aggregatedList_next(request_agg, response_agg)

    if not found_disk_name or not actual_zone:
        return {"status": "error", "message": f"Could not find PVC: {pvc_name} in any zone"}
    
    # --- จบส่วนที่แก้ไข ---

    managed_label_key = "managed_by"
    managed_label_val = "tf-scheduler"
    disk_label_key = "source_disk_name"

    # 2) สร้างชื่อ Snapshot
    short_id = found_disk_name[-10:]
    snap_name = f"mc-{short_id}-{_utc_now().strftime('%Y%m%d-%H%M%S')}".lower()

    # 3) Create snapshot (ใช้ actual_zone ที่หาเจอจริง)
    body = {
        "name": snap_name,
        "labels": {
            managed_label_key: managed_label_val,
            disk_label_key: found_disk_name[:60], 
        },
    }

    op = compute.disks().createSnapshot(
        project=project_id,
        zone=actual_zone, # เปลี่ยนจาก zone เดิมเป็น actual_zone
        disk=found_disk_name,
        body=body,
    ).execute()

    # 4) Cleanup old snapshots (เหมือนเดิม)
    cutoff = _utc_now() - timedelta(minutes=retention_minutes)
    flt = f"labels.{managed_label_key} = {managed_label_val}"

    snaps = []
    req = compute.snapshots().list(project=project_id, filter=flt, maxResults=500)
    while req is not None:
        resp = req.execute()
        snaps.extend(resp.get("items", []))
        req = compute.snapshots().list_next(previous_request=req, previous_response=resp)

    deleted = 0
    for s in snaps:
        ts = s.get("creationTimestamp")
        if not ts: continue
        created = _parse_rfc3339(ts)
        if created < cutoff:
            compute.snapshots().delete(project=project_id, snapshot=s["name"]).execute()
            deleted += 1

    return {
        "status": "ok",
        "target_disk": found_disk_name,
        "target_zone": actual_zone,
        "created_snapshot": snap_name,
        "deleted_count": deleted
    }