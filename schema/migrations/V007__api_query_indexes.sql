create extension if not exists pg_trgm;

create index if not exists ix_artist_name_trgm
    on public.artist using gin (name gin_trgm_ops)
    where name is not null;

create index if not exists ix_artist_real_name_trgm
    on public.artist using gin (real_name gin_trgm_ops)
    where real_name is not null;

create index if not exists ix_label_name_trgm
    on public.label using gin (name gin_trgm_ops)
    where name is not null;

create index if not exists ix_master_title_trgm
    on public.master using gin (title gin_trgm_ops)
    where title is not null;

create index if not exists ix_release_item_title_trgm
    on public.release_item using gin (title gin_trgm_ops)
    where title is not null;

create index if not exists ix_master_year_id
    on public.master (year, id)
    where year is not null;

create index if not exists ix_release_item_country_id
    on public.release_item (lower(country), id)
    where country is not null;

create index if not exists ix_release_item_release_date_id
    on public.release_item (release_date, id)
    where has_valid_year is true;

create index if not exists ix_release_item_is_master_id
    on public.release_item (is_master, id)
    where is_master is not null;

create index if not exists ix_release_item_master_id_id
    on public.release_item (master_id, id)
    where master_id is not null;

create index if not exists ix_release_item_artist_artist_release
    on public.release_item_artist (artist_id, release_item_id);

create index if not exists ix_release_item_credited_artist_artist_release
    on public.release_item_credited_artist (artist_id, release_item_id);

create index if not exists ix_label_release_item_label_release
    on public.label_release_item (label_id, release_item_id);

create index if not exists ix_label_sub_label_sub_parent
    on public.label_sub_label (sub_label_id, parent_label_id);
