/* snap_host: SCD2 history of hosts (timestamp strategy on <stg_host.updated_at>).
   Grain: one row per host version. A new version opens only when <updated_at> increases. */
{% snapshot snap_host %}
{{ config(unique_key='host_id', strategy='timestamp', updated_at='updated_at') }}
select * from {{ ref('stg_host') }}
{% endsnapshot %}
