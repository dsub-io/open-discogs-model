alter table public.discogs_import_run_dump
    add column chunk_size bigint,
    add column total_items bigint,
    add column total_chunks bigint,
    add constraint ck_discogs_import_run_dump_chunk_size
        check (chunk_size is null or chunk_size > 0),
    add constraint ck_discogs_import_run_dump_totals
        check (
            (total_items is null and total_chunks is null)
            or
            (total_items >= 0 and total_chunks >= 0)
        ),
    add constraint ck_discogs_import_run_dump_completed_totals
        check (
            completed_at is null
            or
            (
                chunk_size is not null
                and total_items is not null
                and total_chunks is not null
                and processed_items = total_items
            )
        );

create table public.discogs_import_run_chunk
(
    import_run_id       bigint    not null,
    entity_type         varchar(16) not null,
    chunk_index         bigint    not null
        constraint ck_discogs_import_run_chunk_index
            check (chunk_index >= 0),
    first_item_index    bigint    not null
        constraint ck_discogs_import_run_chunk_first_item_index
            check (first_item_index >= 0),
    item_count          bigint    not null
        constraint ck_discogs_import_run_chunk_item_count
            check (item_count > 0),
    completed_at        timestamp not null default now(),
    constraint pk_discogs_import_run_chunk
        primary key (import_run_id, entity_type, chunk_index),
    constraint uq_discogs_import_run_chunk_first_item
        unique (import_run_id, entity_type, first_item_index),
    constraint fk_discogs_import_run_chunk_run_dump
        foreign key (import_run_id, entity_type)
            references public.discogs_import_run_dump
            on delete cascade
);
