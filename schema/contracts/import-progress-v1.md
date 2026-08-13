# Import progress v1

Durable summary progress is recorded once per import run and entity type in
`discogs_import_run_dump`. `discogs_import_run_chunk` records committed chunks
while a run remains resumable. It never records one row per relation or source
item, and its rows may be removed after a successful run no longer needs them.

`processed_items` is the number of root XML elements whose canonical entity and
complete relation set have committed. Each successful chunk inserts exactly one
`discogs_import_run_chunk` row and increments the summary in the same
transaction as the corresponding catalog writes. A duplicate chunk insert does
not increment the summary. This permits bounded parallel chunk commits without
mistaking a gap for committed work after a crash.

`chunk_size` is fixed before an entity starts. `chunk_index`,
`first_item_index`, and `item_count` identify each source-order range. A retry
may skip only ranges represented by committed chunk rows; an aggregate item
count alone never authorizes a skip.

`last_progress_at` records the last committed progress update. `completed_at`
is set only after the importer reaches a valid end of the entity stream,
records `total_items` and `total_chunks`, verifies that committed chunk indexes
cover the stream without gaps or overlaps, and confirms the committed item sum
equals `total_items`. An import run may become `success` only when every
selected `discogs_import_run_dump` row has `completed_at` set.

A retry creates a new import run. When `force_requested` is false, it may copy
progress from the most recent failed or abandoned run only when all of the
following values match exactly:

- manifest SHA-256;
- entity type and dump ID;
- chunk size;
- entity-specific import contract revision.

`processor` and `processor_version` identify the implementation for operations
and diagnostics; they do not define resume compatibility. Go and Java may
transfer progress when the values above match. Every importer change that can
alter chunk boundaries or canonical output must increment the affected entity's
shared import contract revision before release.

Progress is not resumable if a newer successful checkpoint has overwritten any
selected entity with a different dump or import contract revision. This check
is relative to the failed run's completion time: an older checkpoint does not
invalidate chunks that the failed run committed afterward.

The new run records that source run in `resumed_from_run_id` and copies its
summary and chunk ledger atomically. A forced import starts every entity at zero
and does not resume prior progress. Importers may re-read committed source
elements while locating ranges, but they must not rewrite or recount them.

Once a retry owns a copied ledger, the source rows are transferred atomically.
Other failed-run rows may be pruned only when every entity/dump pair is the
current successful checkpoint with the same import contract revision;
historical success is insufficient. Chunk rows for a successful run may also
be pruned because successful manifest identity, totals, and completion remain
in the run history. Pruning must never remove the only valid ledger from which
an unfinished run can resume.

The progress contract assumes each committed root entity has converged to the
exact relation set represented by the dump. Repeating a chunk after a rollback
must therefore produce the same normalized business state.

Import admission uses exclusive advisory locks for both selected entities and
their reference dependencies. `master` requires `artist` and `master` locks;
`release` requires `artist`, `label`, `master`, and `release` locks because it
reads all three reference sets and updates `master.main_release_id`. Locks are
always acquired in canonical entity order. This prevents a partial import from
filtering against a moving reference set or racing a cross-entity write.
