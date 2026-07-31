# Import manifest v1

An import is identified by the bytes of the selected dumps, not by their
download location.

The manifest contains one entry per selected entity type. Entity types are
limited to `artist`, `label`, `master`, and `release`, may appear only once, and
must all use the same dump date. A normal full import requires all four types.
A deliberately scoped import may contain a dependency-complete subset.

To compute `manifest_sha256`:

1. lowercase every hexadecimal SHA-256 value;
2. sort entries by entity type;
3. encode the following preimage as UTF-8, where `NUL` is byte `0x00`:

   ```text
   open-discogs-manifest/v1\n
   {entity_type}NUL{dump_date:YYYY-MM-DD}NUL{checksum_sha256}\n
   ```

4. compute the lowercase hexadecimal SHA-256 of the complete preimage.

URI, ETag, byte size, processor, and processor version are retained as
provenance but are not part of content identity.

Before starting work, an importer checks for a successful run with the same
manifest fingerprint. It skips that manifest unless force was explicitly
requested. Failed and running records never authorize a skip. At most one
running import of a manifest may exist at a time.

Importers also serialize writes per entity type with PostgreSQL session
advisory locks. The shared two-key namespace is `1329876273`; entity keys are
`artist=1`, `label=2`, `master=3`, and `release=4`. An importer acquires all
requested keys in sorted entity order on one dedicated connection. If any
`pg_try_advisory_lock(namespace, entity_key)` call returns false, it releases
the keys already acquired and does not start. Disjoint entity sets may run
concurrently. Closing the dedicated connection releases every held lock,
including after a process crash.

After acquiring locks, the importer repeats the success and checkpoint checks
to close the preflight race. A candidate whose dump date predates that entity's
checkpoint is rejected. `force` does not bypass this rule. An explicit
`allow_downgrade` option is required and is recorded on the run when an
operator intentionally applies older data.

An importer marks a run successful only after every requested entity type has
completed. A failed or interrupted run remains retryable. Reprocessing a
manifest with force must leave the same normalized business rows as the first
successful import.

The `discogs_import_checkpoint` view exposes the last successfully applied dump
for each entity type. It is derived from immutable run history so checkpoint
dates cannot drift away from the run and dump that produced them.

The adjacent TSV file is the language-neutral conformance vector used by the
Java and Go tests.
