# Import progress v1

Durable progress is recorded once per import run and entity type in
`discogs_import_run_dump`. It does not create one database row per source item
or chunk.

`processed_items` is the number of root XML elements, in source order, whose
canonical entity and complete relation set have committed. An importer advances
this value in the same transaction as the corresponding catalog writes. It
must never advance progress before those writes commit or process chunks out of
source order.

`last_progress_at` records the last committed progress update. `completed_at`
is set only after the importer reaches a valid end of the entity stream and all
catalog writes have committed. An import run may become `success` only when
every selected `discogs_import_run_dump` row has `completed_at` set.

A retry creates a new import run. When `force_requested` is false, it may copy
progress from the most recent failed or abandoned run only when all of the
following values match exactly:

- manifest SHA-256;
- processor name and processor version;
- entity type and dump ID.

The new run records that source run in `resumed_from_run_id`. A forced import
starts every entity at zero and does not resume prior progress. Importers may
re-read or skip already committed source elements while locating the resume
position, but they must not rewrite or recount them as new progress.

The progress contract assumes each committed root entity has converged to the
exact relation set represented by the dump. Repeating a chunk after a rollback
must therefore produce the same normalized business state.
