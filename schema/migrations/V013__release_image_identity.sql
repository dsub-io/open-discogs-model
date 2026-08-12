set lock_timeout = '5s';

alter table public.release_item_image
    add column identity_sha256 bytea,
    add constraint ck_release_item_image_identity_sha256_length
        check (identity_sha256 is null or octet_length(identity_sha256) = 32) not valid;

comment on column public.release_item_image.identity_sha256 is
    'SHA-256 of the canonical release-relation identity v1 image payload; dump importers leave this null because public monthly dumps do not contain images.';

reset lock_timeout;
