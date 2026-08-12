alter table public.discogs_import_run_dump
    add column import_contract_revision integer not null default 1;

alter table public.discogs_import_run_dump
    alter column import_contract_revision drop default,
    add constraint ck_discogs_import_run_dump_import_contract_revision_positive
        check (import_contract_revision > 0);

comment on column public.discogs_import_run_dump.import_contract_revision is
    'Entity semantics revision: pre-V009 rows are 1; V009 uses artist=1, label=1, master=1, release=2 and requires an explicit value.';

alter table public.release_item
    add constraint uq_release_item_master_id_id
        unique (master_id, id);

drop index public.ix_release_item_master_id_id;

alter table public.master
    drop constraint fk_master_main_release_id_release_item,
    add constraint uq_master_main_release_id
        unique (main_release_id),
    add constraint fk_master_id_main_release_id_release_item_master_id_id
        foreign key (id, main_release_id)
            references public.release_item (master_id, id)
            deferrable initially immediate;

create function public.clear_stale_main_release_before_release_master_change()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $trigger$
begin
    update public.master
    set main_release_id = null
    where id = old.master_id
      and main_release_id = old.id;

    return new;
end
$trigger$;

create trigger trg_release_item_clear_stale_main_release
before update of master_id on public.release_item
for each row
when (old.master_id is distinct from new.master_id)
execute function public.clear_stale_main_release_before_release_master_change();
