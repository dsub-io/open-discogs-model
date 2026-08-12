# Legacy Liquibase compatibility v1

This contract permits the shared canonical migration ledger to adopt schema
history written by Java OpenDiscogs Batch releases `1.0.0` through `1.2.1`.
It covers canonical migrations V001 through V007 and Liquibase `5.0.3`
checksum version 9.

[`legacy-liquibase-v1.json`](legacy-liquibase-v1.json) is the machine-readable
source of truth. Its JSON shape is fixed by
[`legacy-liquibase-v1.schema.json`](legacy-liquibase-v1.schema.json). The
manifest binds every migration to the SHA-256 of the original canonical SQL
bytes and to both released Liquibase changeset identities.

## Adoption proof

Liquibase identity is the complete `ID`, `AUTHOR`, and `FILENAME` tuple. An
adopter must find exactly one matching row for every migration in one complete
historical prefix. Missing rows, duplicate identities, unknown execution types,
and histories newer than the selected model artifact fail closed.

The public changelog has an exact checksum for each changeset. Its `EXECUTED`
rows require that checksum. The custom-schema changelog uses `modifySql` with
the `databaseSchema` parameter, so its checksum changes with the schema name and
is never independent proof of canonical state.

V001, V002, V003, V005, and V006 may legitimately be `MARK_RAN` because their
released preconditions used `onFail="MARK_RAN"`. V004 and V007 may only be
`EXECUTED`. Every permitted `MARK_RAN` row and every custom-schema row requires
schema validation in addition to its history identity.

## Schema validation

Released Java histories end at V004, V006, or V007. Each prefix in the manifest
references the same immutable
[`legacy-schema-fingerprint-v1.sql`](legacy-schema-fingerprint-v1.sql) verifier
and a distinct expected fingerprint.

The adopter must:

1. hold the shared schema-migration lock and exclude legacy Liquibase writers;
2. set `search_path` to the quoted target schema followed by `public`;
3. execute the verifier and read its single `fingerprint_input` text value;
4. compute lowercase SHA-256 over the UTF-8 bytes without adding a newline;
5. compare it with the selected prefix and PostgreSQL major in the manifest;
6. insert canonical filename and raw-SQL SHA-256 rows into the shared ledger in
   the same transaction.

The fingerprint includes canonical relations, columns, defaults, constraints,
views, owned sequences, unique indexes, and canonical explicit indexes. It
ignores unrelated tables and additional non-unique DBA indexes. PostgreSQL 15,
16, 17, and 18 are explicitly represented because PostgreSQL 18 renders parts
of the catalog differently. An unlisted PostgreSQL major requires a new model
contract and must not reuse another major's fingerprint.

## Safety boundary

The contract proves that the current catalog matches a released canonical
prefix; it does not prove who created that catalog. It does not validate object
ownership, grants, unrelated objects, additional non-unique indexes, or user
data beyond enforced and validated constraints. A forged `DATABASECHANGELOG`
row cannot bypass the required fingerprint, but a database that was manually
made catalog-equivalent is intentionally indistinguishable from one produced by
the released migration.

Adoption must stop for any mismatch. Repairing a partial legacy schema, choosing
whether to preserve non-canonical objects, and approving a future PostgreSQL
major remain explicit operator actions rather than automatic inference.
