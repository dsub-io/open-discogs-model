create table if not exists public.discogs_dump
(
    id                  bigserial
        constraint pk_discogs_dump
            primary key,
    created_at          timestamp    not null default now(),
    last_modified_at    timestamp    not null default now(),
    etag                varchar(255) not null
        constraint uq_discogs_dump_etag
            unique,
    dump_date           date         not null,
    entity_type         varchar(16)  not null
        constraint ck_discogs_dump_entity_type
            check (entity_type in ('artist', 'label', 'master', 'release')),
    checksum_sha256     char(64)     not null
        constraint ck_discogs_dump_checksum_sha256
            check (checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    size_bytes          bigint       not null
        constraint ck_discogs_dump_size_bytes
            check (size_bytes >= 0),
    uri                 text         not null,
    constraint uq_discogs_dump_date_entity_type_checksum
        unique (dump_date, entity_type, checksum_sha256),
    constraint uq_discogs_dump_id_entity_type
        unique (id, entity_type)
);

create index ix_discogs_dump_date
    on public.discogs_dump (dump_date desc);
