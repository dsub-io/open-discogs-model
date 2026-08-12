set lock_timeout = '5s';

alter table public.release_item_work
    add column identity_sha256 bytea,
    add constraint ck_release_item_work_identity_sha256_length
        check (identity_sha256 is null or octet_length(identity_sha256) = 32) not valid;

comment on column public.release_item_work.identity_sha256 is
    'SHA-256 of the canonical release-relation identity v1 work payload; null only on legacy rows not yet reconciled by contract revision 3.';
comment on column public.discogs_import_run_dump.import_contract_revision is
    'Entity semantics revision: pre-V009 rows are 1; V009 uses release=2; V010-V016-capable importers use release=3 for collision-resistant relation identity.';

reset lock_timeout;
