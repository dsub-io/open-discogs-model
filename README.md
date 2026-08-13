# OpenDiscogs Model

Canonical PostgreSQL schema and generated Java and Go models shared by DSUB
OpenDiscogs services.

This is an independent DSUB project. It is not affiliated with or endorsed by
Discogs.

## Packages

Every release publishes one shared semantic version for both language models.

### Java and jOOQ

The Java artifact is published to Maven Central and exports jOOQ as an API
dependency.

<!-- x-release-please-start-version -->
```groovy
repositories {
    mavenCentral()
}

dependencies {
    implementation 'io.dsub.opendiscogs:open-discogs-model-jooq:0.3.0'
}
```
<!-- x-release-please-end -->

Generated table and record types remain under
`io.dsub.opendiscogs.jooq` so existing Java source does not need package import
changes.

### Go

The Go model is published by the same Git tag as the Maven artifact.

<!-- x-release-please-start-version -->
```bash
go get github.com/dsub-io/open-discogs-model@v0.3.0
```
<!-- x-release-please-end -->

Applications import generated database structs from:

```go
import "github.com/dsub-io/open-discogs-model/model"
```

Canonical SQL migrations can be read from the `schema` package without giving
the model module ownership of when an application migrates its database:

```go
import "github.com/dsub-io/open-discogs-model/schema"

migrations, err := schema.Migrations()
```

## Schema ownership

Files under `schema/migrations` are the only hand-maintained database schema
source. The Java jOOQ classes and Go structs are generated from a PostgreSQL
database created from those ordered migrations.
The Java artifact contains a generated migration inventory and byte-identical
SQL under `io/dsub/opendiscogs/schema/migrations`. JVM consumers use that
namespaced inventory instead of maintaining consumer-owned migration copies.
The legacy `migrations` resource path remains packaged only for compatibility
with released Liquibase consumers.

Canonical migrations require PostgreSQL 15 or newer. Consumers calculate
checksums from the original packaged SQL bytes and only then scope canonical
`public` references to an operator-selected schema.

### Legacy Liquibase compatibility

The model owns a strict
[`legacy-liquibase-v1`](schema/contracts/legacy-liquibase-v1.md) contract for
adopting Java Batch `1.0.0` through `1.2.1` Liquibase history into the shared
canonical migration ledger. The Go `schema.LegacyLiquibaseCompatibility` API
validates its typed manifest against the packaged V001-V007 SQL inventory and
contract resources.

Public `EXECUTED` history requires the exact released Liquibase checksum.
Custom-schema checksums depend on the configured schema name, and permitted
`MARK_RAN` rows do not prove that SQL executed. Those cases require the
model-owned PostgreSQL catalog fingerprint for the complete V004, V006, or V007
historical prefix before any canonical ledger rows are adopted. Unknown
PostgreSQL majors, partial histories, duplicate identities, and fingerprint
mismatches fail closed.

The schema includes the OpenDiscogs catalog tables, immutable dump provenance,
append-only import-run identity, and bounded progress that becomes historical
when a run completes. The shared
[`import-manifest-v1`](schema/contracts/import-manifest-v1.md) contract gives
Java and Go the same content fingerprint and skip/force semantics.
The [`import-progress-v1`](schema/contracts/import-progress-v1.md) contract
keeps one summary row per selected entity and a resumable chunk ledger. The
ledger supports parallel commits without treating gaps as completed work and
may be pruned once a successful run no longer needs it.
Each `discogs_import_run_dump` row also records the entity-specific import
contract revision. Successful checkpoints are reusable across Java and Go only
at the current entity revision; interrupted runs additionally require the same
processor name and version. V009 preserves existing rows at revision `1` and
sets the release convergence contract to revision `2`. Importers that implement
V010-V016 relation identity use `artist=1`, `label=1`, `master=1`, and
`release=3`.
Application-specific Spring Batch metadata and query logic do not belong to
this module.

Dump content versions are unique by date, entity type, and SHA-256. ETag is
indexed for lookup but is not unique because a versioned source path can be
reissued with different bytes.

By default an importer skips a manifest that already has a successful run.
Failed or incomplete runs remain retryable, and an explicit force option may
reprocess a successful manifest. Forced reprocessing must still converge on the
same normalized business state. The `discogs_import_checkpoint` view exposes
the last successfully applied dump date and provenance for each entity type.
Progress advances in the same transaction as a root entity's complete
canonical relation set. A retry may resume only from an identical manifest,
processor, processor version, entity type, and dump, while forced imports
always start from zero.
Per-entity PostgreSQL advisory locks allow disjoint imports to run concurrently
while rejecting overlapping writers. Older dumps are rejected unless a
separate, audited downgrade option is explicitly requested.

The schema also owns the bounded read-path indexes used by the Go API. Trigram
indexes cover artist and label names plus master and release titles; no index is
created for large profile, contact, or notes fields. Reverse relationship keys
and release date, country, master, and master-membership filters have dedicated
indexes. PostgreSQL installations must make the bundled `pg_trgm` extension
available to the migration owner. After a bulk import, run `ANALYZE` before
serving traffic so the planner sees the imported data distribution.
The reproducible synthetic before/after results and their full-dump limitations
are recorded in
[`docs/performance/2026-08-11-api-query-indexes.md`](docs/performance/2026-08-11-api-query-indexes.md).

`label_release_item` identifies a Discogs label credit by release, label, and
catalog number. A release may list the same label more than once with distinct
catalog-number spelling, and every spelling is preserved. PostgreSQL treats a
missing catalog number as one identity value so repeated `NULL` entries do not
create duplicate relations.

A master can name only a release that belongs to that same master as its main
release, and one release cannot be the main release of multiple masters. V009
validates existing data before adding these constraints; it does not silently
repair conflicts. Creating the supporting unique indexes on a populated
production database requires a measured maintenance window and sufficient
temporary disk capacity.

Release credited-artist, format, identifier, image, track, video, and work relations
store the SHA-256 identity defined by
[`release-relation-identity-v1`](schema/contracts/release-relation-identity-v1.md).
V010-V016 deliberately add nullable, unindexed digest columns with unvalidated
checks: PostgreSQL enforces the checks for new writes without rewriting or
scanning existing relation tables. Each relation has its own migration with a
five-second lock timeout so a busy production database rolls back instead of
holding locks across unrelated relation tables. Revision 3 importers transactionally
replace legacy null identities as each release root is processed. This bounded,
resumable phase keeps the existing 32-bit key as a deterministic compatibility
slot; it does not claim that the online index transition is complete.
Monthly public dumps contain no release images, so dump importers do not
backfill `release_item_image`; a future image source requires its own policy and
import boundary. Digest-index cutover for that table remains blocked until a
bounded maintenance job backfills surviving `file_name` rows; rows already lost
to a legacy 32-bit collision cannot be reconstructed from the database alone.

Discogs format quantity can exceed a signed 32-bit integer. V011 preserves the
canonical decimal value in `release_item_format.quantity_text`; the existing
`quantity` column remains populated only when the value fits for compatibility.
Legacy rows remain valid and are filled as their release roots are reconciled.

V017-V038 add the model-owned
[`relation-ordering-v1`](schema/contracts/relation-ordering-v1.md) ordinal to
each catalog relation. These migrations are metadata-only transition steps:
they do not backfill the full catalog or create indexes. Go and Java importers
dual-write source ordinals, readers preserve legacy order with
`coalesce(ordinal, id)`, and bounded owner-scoped backfill belongs to bootstrap
finalization rather than application startup.

## Development

The complete local verification requires Docker, Go 1.26, and Temurin 21.

```bash
sdk env
scripts/verify-generated-models.sh
go test ./...
./gradlew clean build --no-daemon --warning-mode=fail
```

`scripts/verify-generated-models.sh` applies every migration to a temporary
PostgreSQL 18 container, regenerates the Go model from the live catalog, and
fails if the committed generated source is stale. Gradle applies the same
migrations to an ephemeral PostgreSQL database before running jOOQ code
generation.

## Publishing

Conventional commits merged into `main` are collected by Release Please.
Merging its release pull request creates a single semantic-version tag and
GitHub Release. The release workflow then:

1. regenerates and tests the Go module;
2. builds and tests the Java package;
3. signs and publishes `open-discogs-model-jooq` through Maven Central; and
4. verifies the tagged Go module directly from GitHub.

Documentation-only changes do not create a version bump. Credentials and GPG
material are read only from encrypted GitHub Actions secrets.

## Consumers

- [OpenDiscogs Batch](https://github.com/dsub-io/open-discogs-batch)
- [Go OpenDiscogs Batch](https://github.com/dsub-io/go-open-discogs-batch)
- [Go OpenDiscogs API](https://github.com/dsub-io/go-open-discogs-api)

## License

Licensed under the Apache License, Version 2.0. See `LICENSE` and `NOTICE`.
