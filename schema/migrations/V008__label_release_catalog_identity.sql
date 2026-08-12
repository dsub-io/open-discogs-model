alter table public.label_release_item
    drop constraint if exists uq_label_release_item_release_item_id_label_id;

do $migration$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'uq_label_release_item_identity'
          and conrelid = 'public.label_release_item'::regclass
    ) then
        alter table public.label_release_item
            add constraint uq_label_release_item_identity
                unique nulls not distinct
                    (release_item_id, label_id, category_notation);
    end if;
end
$migration$;
