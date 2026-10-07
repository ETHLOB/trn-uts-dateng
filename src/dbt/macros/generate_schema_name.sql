-- Custom schema names as-is in production (silver, gold, datamart); prefixed with the
-- target schema elsewhere (dbt_dev_silver, ...). dbt's built-in generate_schema_name_for_env
-- applies the custom name only when target.name == 'prod'.
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ generate_schema_name_for_env(custom_schema_name, node) }}
{%- endmacro %}
