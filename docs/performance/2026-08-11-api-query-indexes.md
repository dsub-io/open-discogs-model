# API query index benchmark (2026-08-11)

## Result

`V007__api_query_indexes.sql` replaced sequential scans on the measured API
search and reverse-relationship paths with bounded index scans.

| Query | Before p50 / p95 / p99 | After p50 / p95 / p99 | p95 change |
| --- | ---: | ---: | ---: |
| Release title substring | 163.887 / 194.535 / 199.306 ms | 0.111 / 0.136 / 0.142 ms | 99.930% lower (1,430.4x) |
| Releases by artist | 16.717 / 17.309 / 22.187 ms | 0.040 / 0.061 / 0.070 ms | 99.648% lower (283.8x) |

The title query changed from a parallel primary-key scan that rejected 999,997
rows to a bitmap scan on `ix_release_item_title_trgm`. The artist relationship
query changed from a parallel sequential scan of 1,000,000 rows to an index-only
scan on `ix_release_item_artist_artist_release`.

The synthetic database grew from 314,308,287 to 486,389,439 bytes after all
V007 indexes were added: 164.1 MiB, or 54.7%. This is a deliberate read-latency
tradeoff and must be remeasured with the full dump before production sizing.

## Conditions

- Apple M2 Pro host, arm64, 12 Docker CPUs, 8 GiB Docker memory
- PostgreSQL 18.4 Alpine on a 4 GiB tmpfs; no persistent Docker volume
- 1,000,000 releases, 1,000,000 release-artist relations, 250,000 artists,
  250,000 masters, and 100,000 labels
- one client, JIT disabled, five warm-up executions, then 30 measured executions
- identical data and container for the before and after phases; `ANALYZE` ran
  before each phase

Run the benchmark from the repository root:

```sh
scripts/benchmark-api-query-indexes.sh
```

The script prints all latency samples as p50/p95/p99 summaries and the relevant
JSON execution plans. Row counts and run counts can be changed with its
`BENCH_*` environment variables. It owns an exact, labeled container, uses
tmpfs, and verifies that Docker did not create a volume before removing the
container on success, failure, or interruption.

## Limits

This is a warm-cache synthetic query benchmark, not a full-dump capacity claim.
It does not measure concurrent throughput, cold storage I/O, import duration,
RSS, heap allocation, or production index size. The change is database-only, so
Go heap and allocation metrics are not applicable to this measurement. Those
items remain mandatory in the full-dump pre-production rehearsal.
