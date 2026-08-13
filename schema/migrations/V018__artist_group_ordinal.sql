set lock_timeout = '5s';

alter table public.artist_group
    add column ordinal integer,
    add constraint ck_artist_group_ordinal_non_negative
        check (ordinal is null or ordinal >= 0) not valid;

comment on column public.artist_group.ordinal is
    'Zero-based position in the normalized source collection; null only on legacy rows pending bounded owner-scoped backfill.';

reset lock_timeout;
