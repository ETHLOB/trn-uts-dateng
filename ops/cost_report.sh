#!/usr/bin/env bash
# Append a snapshot of this project's GCP costs to ops/logs/costs.log (one JSON object per line).
# Source: Cloud Billing standard usage cost export in BigQuery dataset `billing_export` (US).
# Each run is a snapshot: rows share one `as_of`; readers should use the latest snapshot per usage_date.
# Usage: ops/cost_report.sh
set -euo pipefail
gcloud auth print-access-token >/dev/null 2>&1 || { echo "gcloud is not authenticated (sessions expire about daily): run gcloud auth login" >&2; exit 2; }

cd "$(dirname "$0")"
mkdir -p logs
LOG=logs/costs.log
PROJECT=$(gcloud config get project 2>/dev/null)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# The export table is named after the billing account; find it instead of hard-coding the account ID.
TABLE=$(bq --project_id="$PROJECT" ls --format=json billing_export 2>/dev/null |
  python3 -c "import json,sys; s=sys.stdin.read().strip(); t=[x['tableReference']['tableId'] for x in (json.loads(s) if s else []) if x['tableReference']['tableId'].startswith('gcp_billing_export_v1_')]; print(t[0] if t else '')")

if [ -z "$TABLE" ]; then
  echo "{\"as_of\": \"$NOW\", \"status\": \"export_table_not_yet_available\"}" >> "$LOG"
  echo "Export table not created yet (it can take up to a day after enabling). Logged."
  exit 0
fi

# Daily cost per service, in Sydney time, net of credits (free-trial credits are negative amounts).
bq --project_id="$PROJECT" query --use_legacy_sql=false --format=json --max_rows=10000 "
  SELECT
    CAST(DATE(usage_start_time, 'Australia/Sydney') AS STRING) AS usage_date,
    service.description AS service,
    ROUND(SUM(cost), 4) AS cost,
    ROUND(SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 4) AS credits,
    ANY_VALUE(currency) AS currency
  FROM \`$PROJECT.billing_export.$TABLE\`
  WHERE project.id = '$PROJECT'
  GROUP BY usage_date, service
  ORDER BY usage_date, service" |
python3 -c "
import json, sys
rows = json.load(sys.stdin)
with open('$LOG', 'a') as f:
    if not rows:
        f.write(json.dumps({'as_of': '$NOW', 'status': 'export_table_empty'}) + '\n')
    for r in rows:
        r['as_of'] = '$NOW'
        r['cost'], r['credits'] = float(r['cost']), float(r['credits'])
        r['net'] = round(r['cost'] + r['credits'], 4)
        f.write(json.dumps(r) + '\n')
print(f'Logged {len(rows)} rows; gross {sum(r[\"cost\"] for r in rows):.2f}, net {sum(r[\"net\"] for r in rows):.2f} {rows[0][\"currency\"] if rows else \"\"}')
"
