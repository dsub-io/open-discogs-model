create index if not exists ix_label_release_item_label_catalog_release
    on public.label_release_item (label_id, category_notation, release_item_id)
    where category_notation is not null;

create index if not exists ix_release_item_identifier_type_value_release
    on public.release_item_identifier (
        lower(type),
        decode(md5(value), 'hex'),
        release_item_id
    )
    where type is not null and value is not null;

comment on index public.ix_label_release_item_label_catalog_release is
    'Supports exact Label and catalog-number Release lookup with ID cursor pagination.';

comment on index public.ix_release_item_identifier_type_value_release is
    'Supports exact identifier type and value Release lookup with ID cursor pagination; queries recheck the original value after the bounded MD5 lookup.';
