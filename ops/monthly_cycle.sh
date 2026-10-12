#!/usr/bin/env bash
# One manual monthly cycle of brief Part 3, for one Airbnb file:
#   1. upload data/airbnb/<MM_YYYY.csv> to the Composer bucket (data/airbnb/)
#   2. trigger the DAG bronze_load with an empty `file` (it picks the next month not loaded)
#   3. wait for the run and check that Bronze holds the file's row count
#   4. trigger the dbt Cloud job (DBT_MONTHLY_JOB_ID in .env) and wait for it
# Every run is on demand, one month per call; nothing is scheduled. Appends to ops/logs/monthly_cycle.log.
# Usage: ops/monthly_cycle.sh 06_2020.csv [--dbt-only]   (cloud-sql-proxy must be running on localhost:5433)
#        --dbt-only: the month is already loaded; re-check Bronze and run only step 4.
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
gcloud auth print-access-token >/dev/null 2>&1 || { echo "gcloud is not authenticated: run gcloud auth login" >&2; exit 2; }

FILE=${1:?usage: ops/monthly_cycle.sh MM_YYYY.csv}
[[ $FILE =~ ^[0-9]{2}_[0-9]{4}\.csv$ ]] || { echo "expected MM_YYYY.csv, got $FILE" >&2; exit 2; }
ENV=bde-at3-airflow
LOC=australia-southeast1
PSQL=${PSQL:-/Library/PostgreSQL/18/bin/psql}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
set -a; . ./.env; set +a   # DBT_HOST, DBT_ACCOUNT_ID, DBT_TOKEN, DBT_MONTHLY_JOB_ID, DATABASE_URI (never printed)
LOG=ops/logs/monthly_cycle.log
log() { python3 -c 'import json,sys,datetime; print(json.dumps({"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "file": sys.argv[1], "step": sys.argv[2], "result": sys.argv[3], "detail": sys.argv[4]}))' "$FILE" "$1" "$2" "${3:-}" | tee -a "$LOG"; }

PREFIX=$(gcloud composer environments describe "$ENV" --location "$LOC" --format="value(config.dagGcsPrefix)")
BUCKET=${PREFIX%/dags}
AIRFLOW=$(gcloud composer environments describe "$ENV" --location "$LOC" --format="value(config.airflowUri)")
af() { curl -sf -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json" "$@"; }
dbt_api() { curl -sf -H "Authorization: Token ${DBT_TOKEN}" -H "Content-Type: application/json" "$@"; }
rows() { "$PSQL" "$DATABASE_URI" -At -c "select count(1) from bronze.raw_listings where _source_file = '$FILE'"; }

if [[ ${2:-} == --dbt-only ]]; then SKIP_DAG=1; else SKIP_DAG=0; fi   # resume at step 4 after a fixed check

# 1. upload
if (( ! SKIP_DAG )); then
gcloud storage cp "data/airbnb/$FILE" "$BUCKET/data/airbnb/" --quiet
log upload done "data/airbnb/$FILE"

# 2. trigger the DAG (empty conf: pick_month takes the earliest month not loaded, refusing gaps)
RUN_ID=$(af -X POST "$AIRFLOW/api/v1/dags/bronze_load/dagRuns" -d '{"conf": {}, "note": "Part 3 monthly cycle"}' |
  python3 -c "import json,sys; print(json.load(sys.stdin)['dag_run_id'])")
log dag_trigger done "$RUN_ID"

# 3. wait for the DAG run, then check Bronze
ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$RUN_ID")
while :; do
  STATE=$(af "$AIRFLOW/api/v1/dags/bronze_load/dagRuns/$ENC" | python3 -c "import json,sys; print(json.load(sys.stdin)['state'])")
  [[ $STATE == success || $STATE == failed ]] && break
  sleep 15
done
EXPECTED=$(python3 -c "import csv,sys; print(sum(1 for _ in csv.reader(open(sys.argv[1]))) - 1)" "data/airbnb/$FILE")   # data rows (wc -l misses a last line without newline)
LOADED=$(rows)
log dag_run "$STATE" "bronze rows for $FILE: $LOADED (file: $EXPECTED)"
[[ $STATE == success && $LOADED == "$EXPECTED" ]] || { echo "DAG run or row check failed; dbt not triggered." >&2; exit 1; }
else
EXPECTED=$(python3 -c "import csv,sys; print(sum(1 for _ in csv.reader(open(sys.argv[1]))) - 1)" "data/airbnb/$FILE")
LOADED=$(rows)
log dag_skip "check" "bronze rows for $FILE: $LOADED (file: $EXPECTED)"
[[ $LOADED == "$EXPECTED" ]] || { echo "Row check failed; dbt not triggered." >&2; exit 1; }
fi

# 4. trigger the dbt Cloud job and wait
JOB_RUN=$(dbt_api -X POST "https://$DBT_HOST/api/v2/accounts/$DBT_ACCOUNT_ID/jobs/$DBT_MONTHLY_JOB_ID/run/" \
  -d "{\"cause\": \"Part 3 monthly cycle after loading $FILE\"}" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['id'])")
log dbt_trigger done "run $JOB_RUN"
while :; do
  OUT=$(dbt_api "https://$DBT_HOST/api/v2/accounts/$DBT_ACCOUNT_ID/runs/$JOB_RUN/?include_related=%5B%22run_steps%22%5D" | python3 -c "
import json, sys
r = json.load(sys.stdin)['data']
done = [l.split('Done. ')[-1] for s in r.get('run_steps') or [] for l in (s.get('logs') or '').splitlines() if 'Done. PASS' in l]
print(int(r['is_complete']), r['status_humanized'], done[-1] if done else '')")
  [[ ${OUT%% *} == 1 ]] && break
  sleep 15
done
STATUS=${OUT#1 }
log dbt_run "${STATUS%% *}" "run $JOB_RUN: ${STATUS#* }"
[[ $STATUS == Success* ]]
