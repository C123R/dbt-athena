{% macro athena__create_table_as(temporary, relation, sql) -%}
  {%- set materialized = config.get('materialized', default='table') -%}
  {%- set external_location = config.get('external_location', default=none) -%}
  {%- set partitioned_by = config.get('partitioned_by', default=none) -%}
  {%- set bucketed_by = config.get('bucketed_by', default=none) -%}
  {%- set bucket_count = config.get('bucket_count', default=none) -%}
  {%- set field_delimiter = config.get('field_delimiter', default=none) -%}
  {%- set table_type = config.get('table_type', default='hive') | lower -%}
  {%- set format = config.get('format', default='parquet') -%}
  {%- set write_compression = config.get('write_compression', default=none) -%}
  {%- set s3_data_dir = config.get('s3_data_dir', default=target.s3_data_dir) -%}
  {%- set s3_data_naming = config.get('s3_data_naming', default=target.s3_data_naming) -%}
  {%- set extra_table_properties = config.get('table_properties', default=none) -%}

  {%- set location_property = 'external_location' -%}
  {%- set partition_property = 'partitioned_by' -%}
  {%- set work_group_output_location_enforced = adapter.is_work_group_output_location_enforced() -%}
  {%- set location = adapter.generate_s3_location(relation,
                                                 s3_data_dir,
                                                 s3_data_naming,
                                                 external_location,
                                                 temporary) -%}
  {%- set native_drop = config.get('native_drop', default=false) -%}

  {%- set contract_config = config.get('contract') -%}
  {%- if contract_config.enforced -%}
    {{ get_assert_columns_equivalent(sql) }}
  {%- endif -%}

  {%- if table_type == 'iceberg' -%}
    {%- set location_property = 'location' -%}
    {%- set partition_property = 'partitioning' -%}
    {%- if bucketed_by is not none or bucket_count is not none -%}
      {%- set ignored_bucket_iceberg -%}
      bucketed_by or bucket_count cannot be used with Iceberg tables. You have to use the bucket function
      when partitioning. Will be ignored
      {%- endset -%}
      {%- set bucketed_by = none -%}
      {%- set bucket_count = none -%}
      {% do log(ignored_bucket_iceberg) %}
    {%- endif -%}
    {%- if 'unique' not in s3_data_naming or external_location is not none -%}
      {%- set error_unique_location_iceberg -%}
        You need to have an unique table location when creating Iceberg table since we use the RENAME feature
        to have near-zero downtime.
      {%- endset -%}
      {% do exceptions.raise_compiler_error(error_unique_location_iceberg) %}
    {%- endif -%}
  {%- endif %}

  {%- if native_drop and table_type == 'iceberg' -%}
    {% do log('Config native_drop enabled, skipping direct S3 delete') %}
  {%- else -%}
    {% do adapter.delete_from_s3(location) %}
  {%- endif -%}

  create table {{ relation }}
  with (
    table_type='{{ table_type }}',
    is_external={%- if table_type == 'iceberg' -%}false{%- else -%}true{%- endif %},
  {%- if not work_group_output_location_enforced or table_type == 'iceberg' -%}
    {{ location_property }}='{{ location }}',
  {%- endif %}
  {%- if partitioned_by is not none %}
    {{ partition_property }}=ARRAY{{ partitioned_by | tojson | replace('\"', '\'') }},
  {%- endif %}
  {%- if bucketed_by is not none %}
    bucketed_by=ARRAY{{ bucketed_by | tojson | replace('\"', '\'') }},
  {%- endif %}
  {%- if bucket_count is not none %}
    bucket_count={{ bucket_count }},
  {%- endif %}
  {%- if field_delimiter is not none %}
    field_delimiter='{{ field_delimiter }}',
  {%- endif %}
  {%- if write_compression is not none %}
    write_compression='{{ write_compression }}',
  {%- endif %}
    format='{{ format }}'
  {%- if extra_table_properties is not none -%}
    {%- for prop_name, prop_value in extra_table_properties.items() -%}
    ,
    {{ prop_name }}={{ prop_value }}
    {%- endfor -%}
  {% endif %}
  )
  as
    {{ sql }}
{% endmacro %}
