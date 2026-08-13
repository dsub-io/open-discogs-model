set lock_timeout = '5s';

alter table public.master_video
    add column ordinal integer,
    add constraint ck_master_video_ordinal_non_negative
        check (ordinal is null or ordinal >= 0) not valid;

comment on column public.master_video.ordinal is
    'Zero-based position in the normalized source collection; null only on legacy rows pending bounded owner-scoped backfill.';

reset lock_timeout;
