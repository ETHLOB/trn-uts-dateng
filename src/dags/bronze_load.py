"""
bronze_load: Airflow DAG for Parts 1 and 3 of the Sydney Airbnb + 2016 Census ELT pipeline.

Reads the CSV files from the Composer bucket and loads them into the raw tables of the
bronze schema in Cloud SQL Postgres (tables schemma created by part_1.sql). No schedule: every run
is triggered by hand, one Airbnb month at a time, in chronological order.

Bucket layout (data/ folder of the Composer bucket, mounted at /home/airflow/gcs/data):
    data/census/2016Census_G01_NSW_LGA.csv, data/census/2016Census_G02_NSW_LGA.csv
    data/mapping/NSW_LGA_CODE.csv,          data/mapping/NSW_LGA_SUBURB.csv
    data/airbnb/MM_YYYY.csv                 (05_2020.csv first, then one file per month)

Each run:
    1. Reloads the four reference tables (TRUNCATE + COPY: small, static files).
    2. Picks the Airbnb month to load: the <file> parameter if given, otherwise the earliest
       month in the bucket that is not in bronze.raw_listings yet. A month is refused while an
       earlier month in the bucket is still missing, so the order cannot be broken.
    3. Loads that month (DELETE the file's rows + COPY), so re-running a month is idempotent.

Connection: Cloud SQL Python Connector with IAM database authentication as the environment's
service account (composer-runner). No password required anywhere for enhanced security. The instance
connection name is read from the Airflow Variable <cloudsql_instance>, so no project identifier
is in this file.
"""

import csv
import io
import os
import re
from datetime import UTC, datetime

from airflow.decorators import dag, task
from airflow.exceptions import AirflowSkipException
from airflow.models import Variable
from airflow.models.param import Param

DATA_DIR = "/home/airflow/gcs/data"
SCHEMA = "bronze"

# raw table -> file in the bucket (relative to <DATA_DIR>)
REFERENCE_FILES = {
    "raw_census_g01": "census/2016Census_G01_NSW_LGA.csv",
    "raw_census_g02": "census/2016Census_G02_NSW_LGA.csv",
    "raw_lga_code": "mapping/NSW_LGA_CODE.csv",
    "raw_lga_suburb": "mapping/NSW_LGA_SUBURB.csv",
}
MONTH_FILE = re.compile(r"^(\d{2})_(\d{4})\.csv$")  # MM_YYYY.csv


def connect():
    """Open a Postgres connection as the IAM database user of the Composer service account."""
    from google.cloud.sql.connector import (
        Connector,  # imported here to keep DAG parsing fast
    )

    instance = Variable.get("cloudsql_instance")  # <project>:<region>:<instance>
    project = instance.split(":")[0]
    connector = Connector(refresh_strategy="lazy")
    conn = connector.connect(
        instance,
        "pg8000",
        user=f"composer-runner@{project}.iam",  # IAM user name of a service account: e-mail without .gserviceaccount.com
        db="postgres",
        enable_iam_auth=True,
    )
    return connector, conn


def copy_csv(conn, table, path, truncate):
    """Load one CSV file into bronze.<table> in a single transaction and return the row count.

    - The header must match the table's columns (case-insensitive, same order). Extra trailing
      header cells are allowed only if empty (NSW_LGA_SUBURB.csv has 25 of them) and are dropped.
    - utf-8-sig strips the byte-order mark of NSW_LGA_SUBURB.csv.
    - Each row gets the lineage column <_source_file>; <_loaded_at> takes its default now().
    - Empty fields are written unquoted, so COPY stores them as NULL.
    - <truncate>=True empties the table first (reference data); otherwise only this file's earlier
      rows are deleted, so a month can be reloaded without touching the other months.
    - The row count is checked against the file before COMMIT; on any error nothing is kept.
    """
    source = os.path.basename(path)
    cur = conn.cursor()
    cur.execute(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position",
        (SCHEMA, table),
    )
    # data columns only; the lineage columns (<_source_file>, <_loaded_at>) are not in the file
    cols = [r[0] for r in cur.fetchall() if not r[0].startswith("_")]

    buf = io.StringIO()
    writer = csv.writer(buf)
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = [h.strip().lower() for h in next(reader)]
        if header[: len(cols)] != cols or any(header[len(cols) :]):
            raise ValueError(
                f"{source}: header {header} does not match {SCHEMA}.{table} columns {cols}"
            )
        rows = 0
        for row in reader:
            writer.writerow(row[: len(cols)] + [source])
            rows += 1
    buf.seek(0)

    if truncate:
        cur.execute(f"TRUNCATE {SCHEMA}.{table}")
    else:
        cur.execute(f"DELETE FROM {SCHEMA}.{table} WHERE _source_file = %s", (source,))
    cur.execute(
        f"COPY {SCHEMA}.{table} ({', '.join(cols)}, _source_file) FROM STDIN WITH (FORMAT csv)",
        stream=buf,  # streamed from the worker: server-side COPY FROM '<file>' needs a true superuser
    )
    cur.execute(
        f"SELECT count(1) FROM {SCHEMA}.{table} WHERE _source_file = %s", (source,)
    )
    loaded = cur.fetchone()[0]
    if loaded != rows:
        raise ValueError(
            f"{source}: {rows} rows in the file but {loaded} in {SCHEMA}.{table}"
        )
    conn.commit()
    return rows


def month_key(name):
    """'05_2020.csv' -> (2020, 5), for chronological sorting."""
    mm, yyyy = MONTH_FILE.match(name).groups()
    return int(yyyy), int(mm)


@dag(
    dag_id="bronze_load",
    description="Load census, LGA mapping and one Airbnb month from the Composer bucket into bronze",
    schedule_interval=None,  # triggered by hand only (brief, Part 1.3)
    start_date=datetime(2026, 10, 1, tzinfo=UTC),
    catchup=False,
    max_active_runs=1,  # months must load one at a time, in order
    params={
        "file": Param(
            None,
            type=["null", "string"],
            description="Airbnb file to (re)load, e.g. 05_2020.csv. Empty: the next month not loaded yet.",
        )
    },
    tags=["bronze", "part1", "part3"],
)
def bronze_load():
    @task
    def load_reference(table: str):
        connector, conn = connect()
        try:
            rows = copy_csv(
                conn, table, f"{DATA_DIR}/{REFERENCE_FILES[table]}", truncate=True
            )
        finally:
            conn.close()
            connector.close()
        print(f"{SCHEMA}.{table}: {rows} rows loaded from {REFERENCE_FILES[table]}")
        return rows

    @task
    def pick_month(params=None):
        in_bucket = sorted(
            (f for f in os.listdir(f"{DATA_DIR}/airbnb") if MONTH_FILE.match(f)),
            key=month_key,
        )
        connector, conn = connect()
        try:
            cur = conn.cursor()
            cur.execute(f"SELECT DISTINCT _source_file FROM {SCHEMA}.raw_listings")
            loaded = {r[0] for r in cur.fetchall()}
        finally:
            conn.close()
            connector.close()
        print(
            f"in bucket: {in_bucket}; already loaded: {sorted(loaded, key=month_key)}"
        )

        requested = (params or {}).get("file")
        if not requested:
            pending = [f for f in in_bucket if f not in loaded]
            if not pending:
                raise AirflowSkipException(
                    "Every Airbnb file in the bucket is already loaded."
                )
            return pending[0]
        if requested not in in_bucket:
            raise ValueError(f"{requested} is not in {DATA_DIR}/airbnb")
        missing = [
            f
            for f in in_bucket
            if month_key(f) < month_key(requested) and f not in loaded
        ]
        if missing:
            raise ValueError(f"Load the earlier months first: {missing}")
        return requested

    @task
    def load_listings(file: str):
        connector, conn = connect()
        try:
            rows = copy_csv(
                conn, "raw_listings", f"{DATA_DIR}/airbnb/{file}", truncate=False
            )
        finally:
            conn.close()
            connector.close()
        print(f"{SCHEMA}.raw_listings: {rows} rows loaded from airbnb/{file}")
        return rows

    # One task per reference table (readable names in the graph); all of them before the month.
    references = [
        load_reference.override(task_id=f"load_{t}")(t) for t in REFERENCE_FILES
    ]
    references >> load_listings(pick_month())


bronze_load()
