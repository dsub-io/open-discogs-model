create table if not exists public.label
(
    id               serial
        constraint pk_label
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    contact_info     text,
    data_quality     varchar(255),
    name             varchar(255),
    profile          text
);

create table if not exists public.style
(
    name varchar(255) not null
        constraint pk_style
            primary key
);

create table if not exists public.genre
(
    name varchar(255) not null
        constraint pk_genre
            primary key
);

create table if not exists public.release_item
(
    id                  serial
        constraint pk_release_item
            primary key,
    created_at          timestamp not null,
    last_modified_at    timestamp not null,
    country             varchar(255),
    data_quality        varchar(255),
    has_valid_day       boolean,
    has_valid_month     boolean,
    has_valid_year      boolean,
    is_master           boolean,
    master_id           integer,
    listed_release_date varchar(255),
    notes               text,
    release_date        date,
    status              varchar(255),
    title               varchar(10000)
);

create table if not exists public.release_item_genre
(
    id               serial
        constraint pk_release_item_genre
            primary key,
    created_at       timestamp    not null,
    last_modified_at timestamp    not null,
    genre            varchar(255) not null
        constraint fk_release_item_genre_genre_genre
            references public.genre,
    release_item_id  integer      not null
        constraint fk_release_item_genre_release_item_id_release_item
            references public.release_item,
    constraint uq_release_item_genre_release_item_id_genre
        unique (release_item_id, genre)
);

create table if not exists public.release_item_track
(
    id               serial
        constraint pk_release_item_track
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    hash             integer   not null,
    duration         text,
    position         text,
    title            text,
    release_item_id  integer   not null
        constraint fk_release_item_track_release_item_id_release_item
            references public.release_item,
    constraint uq_release_item_track_release_item_id_hash
        unique (release_item_id, hash)
);

create table if not exists public.label_release_item
(
    id                serial
        constraint pk_label_release_item
            primary key,
    created_at        timestamp not null,
    last_modified_at  timestamp not null,
    category_notation varchar(1000),
    label_id          integer   not null
        constraint fk_label_release_label_id_label
            references public.label,
    release_item_id   integer   not null
        constraint fk_label_release_release_item_id_release_item
            references public.release_item,
    constraint uq_label_release_item_release_item_id_label_id
        unique (release_item_id, label_id)
);

create table if not exists public.release_item_image
(
    id               serial
        constraint pk_release_item_image
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    hash             integer   not null,
    file_name        text,
    release_item_id  integer   not null
        constraint fk_release_item_image_release_item_id_release_item
            references public.release_item,
    constraint uq_release_item_image_release_item_id_hash
        unique (release_item_id, hash)
);

create table if not exists public.release_item_work
(
    id               serial
        constraint pk_release_item_work
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    hash             integer   not null,
    work             varchar(5000),
    label_id         integer   not null
        constraint fk_release_item_work_label_id_label
            references public.label,
    release_item_id  integer   not null
        constraint fk_release_item_work_release_item_id_release_item
            references public.release_item,
    constraint uq_release_item_work_release_item_id_label_id_hash
        unique (release_item_id, label_id, hash)
);

create table if not exists public.release_item_identifier
(
    id               serial
        constraint pk_release_item_identifier
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    hash             integer   not null,
    description      text,
    type             text,
    value            text,
    release_item_id  integer   not null
        constraint fk_release_item_identifier_release_item_id_release_item
            references public.release_item,
    constraint uq_release_item_identifier_release_item_id_hash
        unique (release_item_id, hash)
);

create table if not exists public.master
(
    id               serial
        constraint pk_master
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    data_quality     varchar(255),
    title            varchar(2000),
    year             smallint,
    main_release_id  integer
        constraint fk_master_main_release_id_release_item
            references public.release_item
);

create table if not exists public.master_video
(
    id               serial
        constraint pk_master_video
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    hash             integer   not null,
    description      varchar(15000),
    title            varchar(1000),
    url              varchar(1000),
    master_id        integer   not null
        constraint fk_master_video_master_id_master
            references public.master,
    constraint uq_master_video_master_id_hash
        unique (master_id, hash)
);

alter table public.release_item
    add constraint fk_release_item_master_id_master
        foreign key (master_id) references public.master;

create table if not exists public.master_genre
(
    id               serial
        constraint pk_master_genre
            primary key,
    created_at       timestamp    not null,
    last_modified_at timestamp    not null,
    genre            varchar(255) not null
        constraint fk_master_genre_genre_genre
            references public.genre,
    master_id        integer      not null
        constraint fk_master_genre_master_id_master
            references public.master,
    constraint uq_master_genre_master_id_genre
        unique (master_id, genre)
);

create table if not exists public.master_style
(
    id               serial
        constraint pk_master_style
            primary key,
    created_at       timestamp    not null,
    last_modified_at timestamp    not null,
    master_id        integer      not null
        constraint fk_master_style_master_id_master
            references public.master,
    style            varchar(255) not null
        constraint fk_master_style_style_style
            references public.style,
    constraint uq_master_style_master_id_style
        unique (master_id, style)
);

create table if not exists public.release_item_style
(
    id               serial
        constraint pk_release_item_style
            primary key,
    created_at       timestamp    not null,
    last_modified_at timestamp    not null,
    release_item_id  integer      not null
        constraint fk_release_item_style_release_item_id_release_item
            references public.release_item,
    style            varchar(255) not null
        constraint fk_release_item_style_style_style
            references public.style,
    constraint uq_release_item_style_release_item_id_style
        unique (release_item_id, style)
);

create table if not exists public.label_sub_label
(
    id               serial
        constraint pk_label_sub_label
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    parent_label_id  integer   not null
        constraint fk_label_sub_label_parent_label_id_label
            references public.label,
    sub_label_id     integer   not null
        constraint fk_label_sub_label_sub_label_id_label
            references public.label,
    constraint uq_label_sub_label_parent_label_id_sub_label_id
        unique (parent_label_id, sub_label_id)
);

create table if not exists public.release_item_video
(
    id               serial
        constraint pk_release_item_video
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    hash             integer   not null,
    description      text,
    title            text,
    url              text,
    release_item_id  integer   not null
        constraint fk_release_item_video_release_item_id_release_item
            references public.release_item,
    constraint uq_release_item_video_release_item_id_hash
        unique (release_item_id, hash)
);

create table if not exists public.label_url
(
    id               serial
        constraint pk_label_url
            primary key,
    created_at       timestamp     not null,
    last_modified_at timestamp     not null,
    hash             integer       not null,
    url              varchar(5000) not null,
    label_id         integer       not null
        constraint fk_label_url_label_id_label
            references public.label,
    constraint uq_label_url_label_id_hash
        unique (label_id, hash)
);

create table if not exists public.release_item_format
(
    id               serial
        constraint pk_release_item_format
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    hash             integer   not null,
    description      varchar(10000),
    name             varchar(255),
    quantity         integer,
    text             varchar(5000),
    release_item_id  integer   not null
        constraint fk_release_item_format_release_item_id_release_item
            references public.release_item,
    constraint uq_release_item_format_release_item_id_hash
        unique (release_item_id, hash)
);

create table if not exists public.artist
(
    id               serial
        constraint pk_artist
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    data_quality     varchar(255),
    name             varchar(1000),
    profile          text,
    real_name        varchar(2000)
);

create table if not exists public.artist_alias
(
    id               serial
        constraint pk_artist_alias
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    alias_id         integer   not null
        constraint fk_artist_alias_alias_id_artist
            references public.artist,
    artist_id        integer   not null
        constraint fk_artist_alias_artist_id_artist
            references public.artist,
    constraint uq_artist_alias_artist_id_alias_id
        unique (artist_id, alias_id)
);

create table if not exists public.artist_name_variation
(
    id               serial
        constraint pk_artist_name_variation
            primary key,
    created_at       timestamp     not null,
    hash             integer       not null,
    last_modified_at timestamp     not null,
    name_variation   varchar(2000) not null,
    artist_id        integer       not null
        constraint fk_artist_name_variation_artist_id_artist
            references public.artist,
    constraint uq_artist_name_variation_artist_id_hash
        unique (artist_id, hash)
);

create table if not exists public.master_artist
(
    id               serial
        constraint pk_master_artist
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    artist_id        integer   not null
        constraint fk_master_artist_artist_id_artist
            references public.artist,
    master_id        integer   not null
        constraint fk_master_artist_master_id_master
            references public.master,
    constraint uq_master_artist_master_id_artist_id
        unique (master_id, artist_id)
);

create table if not exists public.release_item_artist
(
    id               serial
        constraint pk_release_item_artist
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    artist_id        integer   not null
        constraint fk_release_item_artist_artist_id_artist
            references public.artist,
    release_item_id  integer   not null
        constraint fk_release_item_artist_release_item_id_release_item
            references public.release_item,
    constraint uq_release_item_artist_release_item_id_artist_id
        unique (release_item_id, artist_id)
);

create table if not exists public.release_item_credited_artist
(
    id               serial
        constraint pk_release_item_credited_artist
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    hash             integer   not null,
    role             varchar(20000),
    artist_id        integer   not null
        constraint fk_release_item_credited_artist_artist_id_artist
            references public.artist,
    release_item_id  integer   not null
        constraint fk_release_item_credited_artist_release_item_id_release_item
            references public.release_item,
    constraint uq_release_item_credited_artist_release_item_id_artist_id_hash
        unique (release_item_id, artist_id, hash)
);

create table if not exists public.artist_url
(
    id               serial
        constraint pk_artist_url
            primary key,
    created_at       timestamp     not null,
    last_modified_at timestamp     not null,
    hash             integer       not null,
    url              varchar(5000) not null,
    artist_id        integer       not null
        constraint fk_artist_url_artist_id_artist
            references public.artist,
    constraint uq_artist_url_artist_id_hash
        unique (artist_id, hash)
);

create table if not exists public.artist_group
(
    id               serial
        constraint pk_artist_group
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    artist_id        integer   not null
        constraint fk_artist_group_artist_id_artist
            references public.artist,
    group_id         integer   not null
        constraint fk_artist_group_group_id_artist
            references public.artist,
    constraint uq_artist_group_artist_id_group_id
        unique (artist_id, group_id)
);

create table if not exists public.artist_member
(
    id               serial
        constraint pk_artist_member
            primary key,
    created_at       timestamp not null,
    last_modified_at timestamp not null,
    artist_id        integer   not null
        constraint fk_artist_member_artist_id_artist
            references public.artist,
    member_id        integer   not null
        constraint fk_artist_member_member_id_artist
            references public.artist,
    constraint uq_artist_member_artist_id_member_id
        unique (artist_id, member_id)
);
