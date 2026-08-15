create function public.discogs_bootstrap_foreign_keys()
returns table
(
    entity_type          text,
    table_name           text,
    constraint_name      text,
    constraint_definition text
)
language sql
immutable
parallel safe
as $function$
    values
        ('artist', 'artist_alias', 'fk_artist_alias_alias_id_artist',
         'foreign key (alias_id) references public.artist'),
        ('artist', 'artist_alias', 'fk_artist_alias_artist_id_artist',
         'foreign key (artist_id) references public.artist'),
        ('artist', 'artist_name_variation', 'fk_artist_name_variation_artist_id_artist',
         'foreign key (artist_id) references public.artist'),
        ('artist', 'artist_url', 'fk_artist_url_artist_id_artist',
         'foreign key (artist_id) references public.artist'),
        ('artist', 'artist_group', 'fk_artist_group_artist_id_artist',
         'foreign key (artist_id) references public.artist'),
        ('artist', 'artist_group', 'fk_artist_group_group_id_artist',
         'foreign key (group_id) references public.artist'),
        ('artist', 'artist_member', 'fk_artist_member_artist_id_artist',
         'foreign key (artist_id) references public.artist'),
        ('artist', 'artist_member', 'fk_artist_member_member_id_artist',
         'foreign key (member_id) references public.artist'),

        ('label', 'label_sub_label', 'fk_label_sub_label_parent_label_id_label',
         'foreign key (parent_label_id) references public.label'),
        ('label', 'label_sub_label', 'fk_label_sub_label_sub_label_id_label',
         'foreign key (sub_label_id) references public.label'),
        ('label', 'label_url', 'fk_label_url_label_id_label',
         'foreign key (label_id) references public.label'),

        ('master', 'master_video', 'fk_master_video_master_id_master',
         'foreign key (master_id) references public.master'),
        ('master', 'master_genre', 'fk_master_genre_genre_genre',
         'foreign key (genre) references public.genre'),
        ('master', 'master_genre', 'fk_master_genre_master_id_master',
         'foreign key (master_id) references public.master'),
        ('master', 'master_style', 'fk_master_style_master_id_master',
         'foreign key (master_id) references public.master'),
        ('master', 'master_style', 'fk_master_style_style_style',
         'foreign key (style) references public.style'),
        ('master', 'master_artist', 'fk_master_artist_artist_id_artist',
         'foreign key (artist_id) references public.artist'),
        ('master', 'master_artist', 'fk_master_artist_master_id_master',
         'foreign key (master_id) references public.master'),

        ('release', 'release_item', 'fk_release_item_master_id_master',
         'foreign key (master_id) references public.master'),
        ('release', 'release_item_genre', 'fk_release_item_genre_genre_genre',
         'foreign key (genre) references public.genre'),
        ('release', 'release_item_genre', 'fk_release_item_genre_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'release_item_track', 'fk_release_item_track_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'label_release_item', 'fk_label_release_label_id_label',
         'foreign key (label_id) references public.label'),
        ('release', 'label_release_item', 'fk_label_release_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'release_item_image', 'fk_release_item_image_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'release_item_work', 'fk_release_item_work_label_id_label',
         'foreign key (label_id) references public.label'),
        ('release', 'release_item_work', 'fk_release_item_work_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'release_item_identifier', 'fk_release_item_identifier_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'master', 'fk_master_id_main_release_id_release_item_master_id_id',
         'foreign key (id, main_release_id) references public.release_item (master_id, id) deferrable initially immediate'),
        ('release', 'release_item_style', 'fk_release_item_style_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'release_item_style', 'fk_release_item_style_style_style',
         'foreign key (style) references public.style'),
        ('release', 'release_item_video', 'fk_release_item_video_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'release_item_format', 'fk_release_item_format_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'release_item_artist', 'fk_release_item_artist_artist_id_artist',
         'foreign key (artist_id) references public.artist'),
        ('release', 'release_item_artist', 'fk_release_item_artist_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item'),
        ('release', 'release_item_credited_artist', 'fk_release_item_credited_artist_artist_id_artist',
         'foreign key (artist_id) references public.artist'),
        ('release', 'release_item_credited_artist', 'fk_release_item_credited_artist_release_item_id_release_item',
         'foreign key (release_item_id) references public.release_item')
$function$;

create function public.prepare_discogs_bootstrap_foreign_keys(target_import_run_id bigint)
returns integer
language plpgsql
security invoker
as $function$
declare
    relation record;
    prepared_count integer := 0;
begin
    if target_import_run_id is null or target_import_run_id <= 0 then
        raise exception 'import run id must be positive';
    end if;

    for relation in
        select foreign_key.*
        from public.discogs_bootstrap_foreign_keys() foreign_key
        join public.discogs_catalog_entity_state catalog_state
          on catalog_state.entity_type = foreign_key.entity_type
        where catalog_state.status = 'importing'
          and catalog_state.operation = 'bootstrap'
          and catalog_state.active_import_run_id = target_import_run_id
        order by foreign_key.table_name, foreign_key.constraint_name
    loop
        execute format(
            'alter table public.%I drop constraint if exists %I',
            relation.table_name,
            relation.constraint_name
        );
        prepared_count := prepared_count + 1;
    end loop;

    return prepared_count;
end
$function$;

create function public.finalize_discogs_bootstrap(target_import_run_id bigint)
returns integer
language plpgsql
security invoker
as $function$
declare
    relation record;
    analyzed_table record;
    finalized_count integer := 0;
begin
    if target_import_run_id is null or target_import_run_id <= 0 then
        raise exception 'import run id must be positive';
    end if;

    for relation in
        select foreign_key.*
        from public.discogs_bootstrap_foreign_keys() foreign_key
        join public.discogs_catalog_entity_state catalog_state
          on catalog_state.entity_type = foreign_key.entity_type
        where catalog_state.status = 'importing'
          and catalog_state.operation = 'bootstrap'
          and catalog_state.active_import_run_id = target_import_run_id
        order by foreign_key.table_name, foreign_key.constraint_name
    loop
        if not exists (
            select 1
            from pg_catalog.pg_constraint constraint_state
            where constraint_state.conrelid = to_regclass(
                    format('public.%I', relation.table_name)
                  )
              and constraint_state.conname = relation.constraint_name
        ) then
            execute format(
                'alter table public.%I add constraint %I %s not valid',
                relation.table_name,
                relation.constraint_name,
                relation.constraint_definition
            );
        end if;

        execute format(
            'alter table public.%I validate constraint %I',
            relation.table_name,
            relation.constraint_name
        );
        finalized_count := finalized_count + 1;
    end loop;

    for analyzed_table in
        select distinct target.table_name
        from (
            select foreign_key.entity_type, foreign_key.table_name
            from public.discogs_bootstrap_foreign_keys() foreign_key
            union all
            values
                ('artist', 'artist'),
                ('label', 'label'),
                ('master', 'master'),
                ('master', 'genre'),
                ('master', 'style'),
                ('release', 'release_item'),
                ('release', 'genre'),
                ('release', 'style')
        ) target(entity_type, table_name)
        join public.discogs_catalog_entity_state catalog_state
          on catalog_state.entity_type = target.entity_type
        where catalog_state.status = 'importing'
          and catalog_state.operation = 'bootstrap'
          and catalog_state.active_import_run_id = target_import_run_id
        order by target.table_name
    loop
        execute format('analyze public.%I', analyzed_table.table_name);
    end loop;

    return finalized_count;
end
$function$;

comment on function public.discogs_bootstrap_foreign_keys() is
    'Canonical inventory of foreign keys deferred only during initial entity bootstrap.';
comment on function public.prepare_discogs_bootstrap_foreign_keys(bigint) is
    'Drops eligible foreign keys for entities in the specified bootstrap run; refresh constraints remain active.';
comment on function public.finalize_discogs_bootstrap(bigint) is
    'Creates deferred foreign keys as NOT VALID, validates them, and analyzes imported bootstrap tables before readiness.';
