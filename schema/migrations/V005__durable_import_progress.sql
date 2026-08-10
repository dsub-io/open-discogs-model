alter table public.discogs_import_run
    add column resumed_from_run_id bigint
        constraint fk_discogs_import_run_resumed_from_run_id
            references public.discogs_import_run;

alter table public.discogs_import_run
    add constraint ck_discogs_import_run_not_self_resumed
        check (resumed_from_run_id is null or resumed_from_run_id <> id);

alter table public.discogs_import_run_dump
    add column processed_items bigint not null default 0,
    add column last_progress_at timestamp,
    add column completed_at timestamp,
    add constraint ck_discogs_import_run_dump_processed_items
        check (processed_items >= 0),
    add constraint ck_discogs_import_run_dump_completion
        check (completed_at is null or last_progress_at is not null);

create or replace view public.discogs_import_checkpoint as
select distinct on (run_dump.entity_type)
    run_dump.entity_type,
    dump.dump_date,
    dump.checksum_sha256,
    dump.size_bytes,
    dump.etag,
    dump.uri,
    import_run.id as import_run_id,
    import_run.processor,
    import_run.processor_version,
    import_run.completed_at as applied_at,
    import_run.resumed_from_run_id
from public.discogs_import_run import_run
join public.discogs_import_run_dump run_dump
    on run_dump.import_run_id = import_run.id
join public.discogs_dump dump
    on dump.id = run_dump.dump_id
   and dump.entity_type = run_dump.entity_type
where import_run.status = 'success'
order by
    run_dump.entity_type,
    import_run.completed_at desc,
    import_run.id desc;
