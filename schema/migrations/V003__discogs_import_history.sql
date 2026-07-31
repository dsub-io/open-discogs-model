create table if not exists public.discogs_import_run
(
    id                  bigserial
        constraint pk_discogs_import_run
            primary key,
    created_at          timestamp    not null default now(),
    started_at          timestamp    not null default now(),
    completed_at        timestamp,
    manifest_sha256     char(64)     not null
        constraint ck_discogs_import_run_manifest_sha256
            check (manifest_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    status              varchar(16)  not null
        constraint ck_discogs_import_run_status
            check (status in ('running', 'success', 'failed')),
    force_requested     boolean      not null default false,
    allow_downgrade_requested
                        boolean      not null default false,
    processor           varchar(64)  not null
        constraint ck_discogs_import_run_processor
            check (processor <> ''),
    processor_version   varchar(255) not null
        constraint ck_discogs_import_run_processor_version
            check (processor_version <> ''),
    failure_message     text,
    constraint ck_discogs_import_run_completion
        check (
            (status = 'running' and completed_at is null and failure_message is null)
            or
            (status = 'success' and completed_at is not null and failure_message is null)
            or
            (status = 'failed' and completed_at is not null)
        )
);

create unique index uq_discogs_import_run_manifest_running
    on public.discogs_import_run (manifest_sha256)
    where status = 'running';

create index ix_discogs_import_run_manifest_success
    on public.discogs_import_run (manifest_sha256, completed_at desc)
    where status = 'success';

create table if not exists public.discogs_import_run_dump
(
    import_run_id       bigint      not null
        constraint fk_discogs_import_run_dump_import_run_id
            references public.discogs_import_run
            on delete cascade,
    entity_type         varchar(16) not null
        constraint ck_discogs_import_run_dump_entity_type
            check (entity_type in ('artist', 'label', 'master', 'release')),
    dump_id             bigint      not null,
    constraint pk_discogs_import_run_dump
        primary key (import_run_id, entity_type),
    constraint fk_discogs_import_run_dump_dump_id_entity_type
        foreign key (dump_id, entity_type)
            references public.discogs_dump (id, entity_type)
);

create index ix_discogs_import_run_dump_dump_id
    on public.discogs_import_run_dump (dump_id);

create view public.discogs_import_checkpoint as
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
    import_run.completed_at as applied_at
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
