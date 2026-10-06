#!/usr/bin/env bash
# Lifecycle of the Cloud Composer environment, with an evidence gate before deletion.
# Every action is appended to ops/logs/composer.log (JSON Lines).
#
#   ops/composer.sh up         create the environment (about 25 min) and install the DAG's packages
#   ops/composer.sh status     environment state, bucket, Airflow UI, nightly safety-net state
#   ops/composer.sh evidence   export DAG run history and task logs to ops/logs/airflow/
#   ops/composer.sh hold       skip tonight's automatic snapshot + delete (resumes itself at 05:00)
#   ops/composer.sh down       refuse unless evidence is fresh, then save a snapshot and delete
#   ops/composer.sh down --force   delete without the evidence gate (logged as forced)
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1   # never block on an interactive gcloud prompt
gcloud auth print-access-token >/dev/null 2>&1 || { echo "gcloud is not authenticated (sessions expire about daily): run gcloud auth login" >&2; exit 2; }

ENV=bde-at3-airflow
LOC=australia-southeast1
IMAGE=composer-3-airflow-2.11.1-build.20   # Airflow 2: the brief asks for schedule_interval=None, removed in Airflow 3
PROJECT=$(gcloud config get project 2>/dev/null)
SA="composer-runner@$PROJECT.iam.gserviceaccount.com"
PYPI="cloud-sql-python-connector[pg8000]>=1.12"
REAPER_JOBS="composer-nightly-snapshot composer-nightly-delete"   # created in E16; paused by `hold`
EVIDENCE_MAX_AGE_MIN=120

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SELF")"
mkdir -p logs/airflow
LOG=logs/composer.log

log() {  # log <action> <result> [detail]
  python3 -c 'import json,sys,datetime; print(json.dumps({"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "env": sys.argv[1], "action": sys.argv[2], "result": sys.argv[3], "detail": sys.argv[4]}))' \
    "$ENV" "$1" "$2" "${3:-}" >> "$LOG"
}

exists() { gcloud composer environments describe "$ENV" --location "$LOC" --format="value(state)" 2>/dev/null || true; }   # empty when absent
bucket() { gcloud composer environments describe "$ENV" --location "$LOC" --format="value(config.dagGcsPrefix)" | sed 's#/dags$##'; }

case "${1:-status}" in
  up)
    if [ -n "$(exists)" ]; then echo "Environment already exists ($(exists))."; exit 0; fi
    log up started "$IMAGE small"
    gcloud composer environments create "$ENV" --location "$LOC" --image-version "$IMAGE" \
      --environment-size small --service-account "$SA" --labels project=trn-uts-dateng
    gcloud composer environments update "$ENV" --location "$LOC" --update-pypi-package "$PYPI"
    log up done "bucket $(bucket | sed "s/$PROJECT/<gcp-project>/g")"
    "$SELF" status
    ;;

  status)
    STATE=$(exists); echo "environment: ${STATE:-absent}"
    if [ -n "$STATE" ]; then
      echo "bucket:      $(bucket)"
      echo "airflow ui:  $(gcloud composer environments describe "$ENV" --location "$LOC" --format='value(config.airflowUri)')"
    fi
    for J in $REAPER_JOBS; do
      echo "safety net:  $J $(gcloud scheduler jobs describe "$J" --location "$LOC" --format='value(state,schedule)' 2>/dev/null || echo 'not created')"
    done
    ;;

  evidence)
    [ -n "$(exists)" ] || { echo "No environment, nothing to export."; exit 1; }
    STAMP=$(date -u +%Y%m%dT%H%M%SZ); OUT="logs/airflow/$STAMP"; mkdir -p "$OUT"
    for DAG in $(gcloud composer environments run "$ENV" --location "$LOC" dags list -- -o plain 2>/dev/null | awk 'NR>1 {print $1}'); do
      gcloud composer environments run "$ENV" --location "$LOC" dags list-runs -- -d "$DAG" -o json > "$OUT/runs_$DAG.json" 2>/dev/null || true
    done
    gcloud storage rsync --recursive "$(bucket)/logs" "$OUT/task_logs" --quiet || true
    touch logs/airflow/.last_evidence
    log evidence done "$OUT"
    echo "Exported to ops/$OUT. Take the Airflow UI screenshots (DAG graph, grid, run details) before 'down'."
    ;;

  hold)
    for J in $REAPER_JOBS; do gcloud scheduler jobs pause "$J" --location "$LOC" --quiet; done
    log hold done "nightly snapshot+delete paused; composer-reaper-resume re-enables them at 05:00"
    echo "Tonight's automatic delete is skipped. It re-arms itself at 05:00."
    ;;

  down)
    [ -n "$(exists)" ] || { echo "No environment to delete."; exit 0; }
    if [ "${2:-}" != "--force" ]; then
      MARK=logs/airflow/.last_evidence
      if [ ! -f "$MARK" ] || [ -n "$(find "$MARK" -mmin +$EVIDENCE_MAX_AGE_MIN)" ]; then
        echo "Refusing: no evidence export in the last $EVIDENCE_MAX_AGE_MIN minutes. Run 'ops/composer.sh evidence' and take screenshots first, or use --force."
        log down refused "evidence missing or stale"; exit 1
      fi
    fi
    log down started "${2:-gated}"
    gcloud composer environments snapshots save "$ENV" --location "$LOC"   # keeps the Airflow DB (run history) in the bucket
    gcloud composer environments delete "$ENV" --location "$LOC" --quiet   # the bucket and its snapshots are kept
    log down done "snapshot saved, environment deleted"
    ;;

  *) sed -n '2,11p' "$SELF"; exit 1 ;;
esac
