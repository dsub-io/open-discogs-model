create table public.discogs_catalog_entity_state
(
    entity_type                  varchar(16) not null
        constraint pk_discogs_catalog_entity_state
            primary key
        constraint ck_discogs_catalog_entity_state_entity_type
            check (entity_type in ('artist', 'label', 'master', 'release')),
    status                       varchar(24) not null
        constraint ck_discogs_catalog_entity_state_status
            check (status in ('bootstrap_pending', 'importing', 'ready', 'failed')),
    operation                    varchar(16)
        constraint ck_discogs_catalog_entity_state_operation
            check (operation in ('bootstrap', 'refresh')),
    active_import_run_id         bigint
        constraint fk_discogs_catalog_entity_state_active_run
            references public.discogs_import_run,
    last_successful_import_run_id bigint
        constraint fk_discogs_catalog_entity_state_successful_run
            references public.discogs_import_run,
    ready_at                     timestamp,
    updated_at                   timestamp not null default now(),
    failure_message              text,
    constraint ck_discogs_catalog_entity_state_transition_shape
        check (
            (
                status = 'bootstrap_pending'
                and operation = 'bootstrap'
                and active_import_run_id is null
                and last_successful_import_run_id is null
                and ready_at is null
                and failure_message is null
            )
            or
            (
                status = 'importing'
                and operation is not null
                and active_import_run_id is not null
                and failure_message is null
            )
            or
            (
                status = 'ready'
                and operation is null
                and active_import_run_id is null
                and last_successful_import_run_id is not null
                and ready_at is not null
                and failure_message is null
            )
            or
            (
                status = 'failed'
                and operation is not null
                and active_import_run_id is null
                and failure_message is not null
            )
        )
);

insert into public.discogs_catalog_entity_state
    (
        entity_type,
        status,
        operation,
        last_successful_import_run_id,
        ready_at
    )
select
    entity.entity_type,
    case when checkpoint.import_run_id is null then 'bootstrap_pending' else 'ready' end,
    case when checkpoint.import_run_id is null then 'bootstrap' else null end,
    checkpoint.import_run_id,
    checkpoint.applied_at
from (
    values ('artist'), ('label'), ('master'), ('release')
) as entity(entity_type)
left join public.discogs_import_checkpoint checkpoint
    on checkpoint.entity_type = entity.entity_type;

create unique index uq_discogs_catalog_entity_state_active_run
    on public.discogs_catalog_entity_state (active_import_run_id, entity_type)
    where active_import_run_id is not null;

create view public.discogs_catalog_readiness as
select
    bool_and(status = 'ready') as ready,
    case
        when bool_or(status = 'failed') then 'failed'
        when bool_or(status = 'importing') then 'importing'
        when bool_or(status = 'bootstrap_pending') then 'bootstrap_pending'
        else 'ready'
    end as status,
    count(*) filter (where status = 'ready') as ready_entities,
    count(*) as required_entities,
    max(updated_at) as updated_at
from public.discogs_catalog_entity_state;

comment on table public.discogs_catalog_entity_state is
    'Durable per-entity bootstrap and refresh state owned by canonical import finalization.';
comment on view public.discogs_catalog_readiness is
    'Aggregate serving readiness; true only after every required entity is finalized.';
