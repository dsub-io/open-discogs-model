set lock_timeout = '5s';

alter table public.release_item_format
    add column identity_sha256 bytea,
    add column quantity_text text,
    add constraint ck_release_item_format_identity_sha256_length
        check (identity_sha256 is null or octet_length(identity_sha256) = 32) not valid,
    add constraint ck_release_item_format_quantity_text_decimal
        check (
            quantity_text is null
            or quantity_text ~ '^(0|[1-9][0-9]*)$'
        ) not valid,
    add constraint ck_release_item_format_quantity_consistent
        check (
            identity_sha256 is null
            or case
                when quantity_text is null then quantity is null
                when char_length(quantity_text) < 10
                    then quantity is not null and quantity::text = quantity_text
                when char_length(quantity_text) = 10
                    and quantity_text collate "C" <= '2147483647'
                    then quantity is not null and quantity::text = quantity_text
                else quantity is null
            end
        ) not valid;

comment on column public.release_item_format.identity_sha256 is
    'SHA-256 of the canonical release-relation identity v1 format payload; null only on legacy rows not yet reconciled by contract revision 3.';
comment on column public.release_item_format.quantity is
    'Compatibility integer quantity when the canonical Discogs quantity fits signed 32-bit storage.';
comment on column public.release_item_format.quantity_text is
    'Canonical non-negative decimal Discogs quantity without leading zeroes; preserves values beyond signed 32-bit storage.';

reset lock_timeout;
