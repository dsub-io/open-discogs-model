set lock_timeout = '5s';

alter table public.artist_alias drop column created_at;
alter table public.artist_group drop column created_at;
alter table public.artist_member drop column created_at;
alter table public.artist_name_variation drop column created_at;
alter table public.artist_url drop column created_at;
alter table public.label_sub_label drop column created_at;
alter table public.label_url drop column created_at;
alter table public.master_artist drop column created_at;
alter table public.master_genre drop column created_at;
alter table public.master_style drop column created_at;
alter table public.master_video drop column created_at;
alter table public.label_release_item drop column created_at;
alter table public.release_item_artist drop column created_at;
alter table public.release_item_credited_artist drop column created_at;
alter table public.release_item_format drop column created_at;
alter table public.release_item_genre drop column created_at;
alter table public.release_item_identifier drop column created_at;
alter table public.release_item_image drop column created_at;
alter table public.release_item_style drop column created_at;
alter table public.release_item_track drop column created_at;
alter table public.release_item_video drop column created_at;
alter table public.release_item_work drop column created_at;

comment on column public.artist_alias.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.artist_group.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.artist_member.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.artist_name_variation.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.artist_url.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.label_sub_label.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.label_url.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.master_artist.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.master_genre.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.master_style.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.master_video.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.label_release_item.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_artist.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_credited_artist.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_format.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_genre.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_identifier.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_image.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_style.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_track.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_video.last_modified_at is
    'Source observation time of the most recent canonical payload.';
comment on column public.release_item_work.last_modified_at is
    'Source observation time of the most recent canonical payload.';

reset lock_timeout;
