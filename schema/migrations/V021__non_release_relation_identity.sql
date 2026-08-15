set lock_timeout = '5s';

alter table public.artist_name_variation
    add column identity_sha256 bytea,
    add constraint ck_artist_name_variation_identity_sha256_length
        check (identity_sha256 is null or octet_length(identity_sha256) = 32) not valid;

comment on column public.artist_name_variation.identity_sha256 is
    'SHA-256 of the canonical non-release relation identity v1 name-variation payload; null only on legacy rows not yet reconciled by artist contract revision 2.';

alter table public.artist_url
    add column identity_sha256 bytea,
    add constraint ck_artist_url_identity_sha256_length
        check (identity_sha256 is null or octet_length(identity_sha256) = 32) not valid;

comment on column public.artist_url.identity_sha256 is
    'SHA-256 of the canonical non-release relation identity v1 artist-URL payload; null only on legacy rows not yet reconciled by artist contract revision 2.';

alter table public.label_url
    add column identity_sha256 bytea,
    add constraint ck_label_url_identity_sha256_length
        check (identity_sha256 is null or octet_length(identity_sha256) = 32) not valid;

comment on column public.label_url.identity_sha256 is
    'SHA-256 of the canonical non-release relation identity v1 label-URL payload; null only on legacy rows not yet reconciled by label contract revision 2.';

alter table public.master_video
    add column identity_sha256 bytea,
    add constraint ck_master_video_identity_sha256_length
        check (identity_sha256 is null or octet_length(identity_sha256) = 32) not valid;

comment on column public.master_video.identity_sha256 is
    'SHA-256 of the canonical non-release relation identity v1 master-video payload; null only on legacy rows not yet reconciled by master contract revision 2.';

reset lock_timeout;
