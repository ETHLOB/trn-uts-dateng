{#
    Operational check, not part of the warehouse: proves that a dbt run can reach Cloud SQL,
    and shows which client address it came from and whether the session is encrypted.
    Run: dbt run-operation connection_check
#}
{% macro connection_check() %}
    {% set sql %}
        select
            current_user                          as db_user,
            current_database()                    as db_name,
            host(inet_client_addr())              as client_ip,
            (select ssl from pg_stat_ssl where pid = pg_backend_pid()) as ssl,
            split_part(version(), ' on ', 1)      as server_version
    {% endset %}
    {% set row = run_query(sql).rows[0] %}
    {{ log("connection_check: user=" ~ row["db_user"] ~ " db=" ~ row["db_name"] ~ " client_ip=" ~ row["client_ip"] ~ " ssl=" ~ row["ssl"] ~ " server=" ~ row["server_version"], info=True) }}
{% endmacro %}
