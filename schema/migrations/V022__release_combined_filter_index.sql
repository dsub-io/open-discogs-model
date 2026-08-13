create index if not exists ix_release_item_country_master_id_date
    on public.release_item (lower(country), is_master, id, release_date)
    where has_valid_year is true;

comment on index public.ix_release_item_country_master_id_date is
    'Bounds country, master-status, and release-date API filtering while preserving cursor ID order.';
