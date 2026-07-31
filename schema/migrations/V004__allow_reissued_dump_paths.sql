alter table public.discogs_dump
    drop constraint if exists uq_discogs_dump_etag;

create index if not exists ix_discogs_dump_etag
    on public.discogs_dump (etag);
