-- Produces the canonical PostgreSQL catalog fingerprint for a legacy prefix.
-- The caller must set search_path to the target schema before executing this query.
with target_schema(schema_name) as (
    select current_schema()
),
relation_names(relation_name) as (
    values
        ('artist'),
        ('artist_alias'),
        ('artist_group'),
        ('artist_member'),
        ('artist_name_variation'),
        ('artist_url'),
        ('discogs_dump'),
        ('discogs_import_checkpoint'),
        ('discogs_import_run'),
        ('discogs_import_run_chunk'),
        ('discogs_import_run_dump'),
        ('genre'),
        ('label'),
        ('label_release_item'),
        ('label_sub_label'),
        ('label_url'),
        ('master'),
        ('master_artist'),
        ('master_genre'),
        ('master_style'),
        ('master_video'),
        ('release_item'),
        ('release_item_artist'),
        ('release_item_credited_artist'),
        ('release_item_format'),
        ('release_item_genre'),
        ('release_item_identifier'),
        ('release_item_image'),
        ('release_item_style'),
        ('release_item_track'),
        ('release_item_video'),
        ('release_item_work'),
        ('style')
),
explicit_index_names(index_name) as (
    values
        ('ix_discogs_dump_date'),
        ('ix_discogs_dump_etag'),
        ('ix_discogs_import_run_dump_dump_id'),
        ('ix_discogs_import_run_manifest_running'),
        ('ix_discogs_import_run_manifest_success'),
        ('ix_artist_name_trgm'),
        ('ix_artist_real_name_trgm'),
        ('ix_label_name_trgm'),
        ('ix_master_title_trgm'),
        ('ix_release_item_title_trgm'),
        ('ix_master_year_id'),
        ('ix_release_item_country_id'),
        ('ix_release_item_release_date_id'),
        ('ix_release_item_is_master_id'),
        ('ix_release_item_master_id_id'),
        ('ix_release_item_artist_artist_release'),
        ('ix_release_item_credited_artist_artist_release'),
        ('ix_label_release_item_label_release'),
        ('ix_label_sub_label_sub_parent')
),
relations as (
    select relation.oid, relation.relname, relation.relkind, relation.relpersistence
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    join target_schema target on target.schema_name = namespace.nspname
    join relation_names expected on expected.relation_name = relation.relname
),
descriptors(kind, object_name, definition) as (
    select
        'relation',
        relation.relname,
        relation.relkind::text || '|' || relation.relpersistence::text
    from relations relation

    union all

    select
        'column',
        relation.relname || '.' || attribute.attname,
        format_type(attribute.atttypid, attribute.atttypmod)
            || '|' || attribute.attnotnull::text
            || '|' || attribute.attidentity::text
            || '|' || attribute.attgenerated::text
            || '|' || coalesce(
                replace(
                    pg_get_expr(default_value.adbin, default_value.adrelid),
                    target.schema_name || '.',
                    '<schema>.'
                ),
                ''
            )
    from relations relation
    join pg_attribute attribute
        on attribute.attrelid = relation.oid
       and attribute.attnum > 0
       and not attribute.attisdropped
    cross join target_schema target
    left join pg_attrdef default_value
        on default_value.adrelid = attribute.attrelid
       and default_value.adnum = attribute.attnum

    union all

    select
        'constraint',
        relation.relname || '.' || constraint_definition.conname,
        constraint_definition.contype::text
            || '|' || constraint_definition.convalidated::text
            || '|' || replace(
                pg_get_constraintdef(constraint_definition.oid, false),
                target.schema_name || '.',
                '<schema>.'
            )
    from relations relation
    join pg_constraint constraint_definition
        on constraint_definition.conrelid = relation.oid
    cross join target_schema target

    union all

    select
        'index',
        relation.relname || '.' || index_relation.relname,
        index_metadata.indisunique::text
            || '|' || index_metadata.indisprimary::text
            || '|' || index_metadata.indisvalid::text
            || '|' || index_metadata.indisready::text
            || '|' || replace(
                pg_get_indexdef(index_metadata.indexrelid),
                target.schema_name || '.',
                '<schema>.'
            )
    from relations relation
    join pg_index index_metadata on index_metadata.indrelid = relation.oid
    join pg_class index_relation on index_relation.oid = index_metadata.indexrelid
    cross join target_schema target
    where index_metadata.indisunique
       or index_relation.relname in (select index_name from explicit_index_names)

    union all

    select
        'sequence',
        sequence_relation.relname,
        format_type(sequence_metadata.seqtypid, -1)
            || '|' || sequence_metadata.seqstart::text
            || '|' || sequence_metadata.seqincrement::text
            || '|' || sequence_metadata.seqmin::text
            || '|' || sequence_metadata.seqmax::text
            || '|' || sequence_metadata.seqcache::text
            || '|' || sequence_metadata.seqcycle::text
    from relations relation
    join pg_depend dependency
        on dependency.refclassid = 'pg_class'::regclass
       and dependency.refobjid = relation.oid
       and dependency.classid = 'pg_class'::regclass
       and dependency.deptype in ('a', 'i')
    join pg_class sequence_relation
        on sequence_relation.oid = dependency.objid
       and sequence_relation.relkind = 'S'
    join pg_sequence sequence_metadata on sequence_metadata.seqrelid = sequence_relation.oid

    union all

    select
        'view',
        relation.relname,
        replace(
            regexp_replace(pg_get_viewdef(relation.oid, false), '\s+', ' ', 'g'),
            target.schema_name || '.',
            '<schema>.'
        )
    from relations relation
    cross join target_schema target
    where relation.relkind = 'v'
)
select coalesce(
    string_agg(
        kind || chr(31) || object_name || chr(31) || definition,
        chr(10)
        order by kind, object_name, definition
    ),
    ''
) as fingerprint_input
from descriptors;
