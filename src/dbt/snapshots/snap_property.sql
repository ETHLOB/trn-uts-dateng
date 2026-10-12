/* snap_property: SCD2 history of listing properties (timestamp strategy on <stg_property.updated_at>).
   Grain: one row per listing version. A new version opens only when <updated_at> increases. */
{% snapshot snap_property %}
{{ config(unique_key='listing_id', strategy='timestamp', updated_at='updated_at') }}
select * from {{ ref('stg_property') }}
{% endsnapshot %}
