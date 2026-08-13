# Relation ordering v1

This contract defines the observable order of catalog relation collections.
Relation `id` is transitional storage and is not a semantic ordering key.

## Ordinal

Every catalog relation stores a nullable `ordinal integer` with these rules:

- zero-based position in the normalized source collection for one owner;
- assigned before exact-duplicate collapse, so gaps are valid;
- exact duplicates retain the first source ordinal;
- excluded invalid references do not renumber later relations;
- conflicting payloads fail before an ordinal is persisted;
- refresh updates an existing canonical relation when its source position moves;
- ordinal is not part of relation identity.

An integer is sufficient because one owner's source collection cannot contain
more than PostgreSQL's signed 32-bit row or array limits. It avoids four bytes
per row compared with `bigint` across relation tables containing hundreds of
millions of rows.

## Owner scopes

| Relation | Owner column |
| --- | --- |
| `artist_alias` | `artist_id` |
| `artist_group` | `artist_id` |
| `artist_member` | `artist_id` |
| `artist_name_variation` | `artist_id` |
| `artist_url` | `artist_id` |
| `label_sub_label` | `parent_label_id` |
| `label_url` | `label_id` |
| `master_artist` | `master_id` |
| `master_genre` | `master_id` |
| `master_style` | `master_id` |
| `master_video` | `master_id` |
| `label_release_item` | `release_item_id` |
| `release_item_artist` | `release_item_id` |
| `release_item_credited_artist` | `release_item_id` |
| `release_item_format` | `release_item_id` |
| `release_item_genre` | `release_item_id` |
| `release_item_identifier` | `release_item_id` |
| `release_item_image` | `release_item_id` |
| `release_item_style` | `release_item_id` |
| `release_item_track` | `release_item_id` |
| `release_item_video` | `release_item_id` |
| `release_item_work` | `release_item_id` |

## Legacy transition

V017-V038 add nullable ordinals without defaults, heap rewrites, indexes, or
full-table scans. During dual-write, readers order by `coalesce(ordinal, id)`.
This preserves the exact prior surrogate-ID order for legacy rows while newly
refreshed owner scopes use source order.

Legacy backfill is owner-scoped and sets:

```sql
row_number() over (partition by owner_id order by id) - 1
```

One owner's relation set is updated in one transaction. Backfill must record
run ownership and progress, validate null/negative/duplicate ordinals, and build
owner-order indexes in the explicit bootstrap finalization phase. It must not be
hidden inside a startup migration.

After every importer and reader uses ordinal and backfill validation succeeds,
a later migration may make ordinal non-null and remove relation surrogate IDs,
their primary-key indexes, and owned sequences. Canonical identity constraints
and reverse lookup indexes remain.

## Mutation time

Catalog relations store one timestamp: `last_modified_at`. It is the source
observation time attached to the most recent accepted canonical payload or
ordinal mutation. An unchanged refresh does not update it. Relation insertion
time is not a separate catalog fact, so V039 removes the duplicate
`created_at`; root entity timestamps keep their existing contract.
