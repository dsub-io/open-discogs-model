set lock_timeout = '5s';

alter table public.release_item_track
    add column identity_sha256 bytea,
    add constraint ck_release_item_track_identity_sha256_length
        check (identity_sha256 is null or octet_length(identity_sha256) = 32) not valid;

comment on column public.release_item_track.identity_sha256 is
    'SHA-256 of the canonical release-relation identity v1 track payload; null only on legacy rows not yet reconciled by contract revision 3.';

reset lock_timeout;
