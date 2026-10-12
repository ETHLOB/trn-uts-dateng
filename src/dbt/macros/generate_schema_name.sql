-- Custom schema names as-is in production (silver, gold, datamart); every other target
-- writes all layers to its own target schema (dbt_dev locally). dbt's built-in generate_schema_name_for_env
-- applies the custom name only when <target.name> == 'prod'.
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ generate_schema_name_for_env(custom_schema_name, node) }}
{%- endmacro %}
