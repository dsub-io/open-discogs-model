# Combined release filter index benchmark (2026-08-13)

## Result

`V022__release_combined_filter_index.sql` bounds the API query that combines
country, master status, release date, and cursor filters.

| Query | Before p50 / p95 / p99 | After p50 / p95 / p99 | p99 change |
| --- | ---: | ---: | ---: |
| Combined release filter | 5.792 / 6.610 / 6.856 ms | 0.185 / 0.208 / 0.225 ms | 96.7% lower |

Before V022, PostgreSQL used `ix_release_item_release_date_id`, visited 4,386
heap blocks, filtered country and master status, and performed a top-N sort.
After V022 it used an ordered scan on
`ix_release_item_country_master_id_date`, returned 31 rows from 53 shared-buffer
hits, and did not sort or use temporary blocks.

The new index was 31,522,816 bytes for 1,000,000 synthetic releases. The test
database changed from 486,405,823 to 517,953,215 bytes, an increase of
31,547,392 bytes or 6.5% after the earlier V007 API indexes were already
present.

## Conditions

- Apple M2 Pro host, arm64, 12 Docker CPUs, 8 GiB Docker memory
- PostgreSQL 18.4 Alpine on a 4 GiB tmpfs; no persistent Docker volume
- 1,000,000 releases, 1,000,000 release-artist relations, 250,000 artists,
  250,000 masters, and 100,000 labels
- one client, JIT disabled, five warm-up executions, then 30 measured executions
- identical data and container before and after V022; `ANALYZE` ran before each
  phase

Run from the model repository root:

```sh
scripts/benchmark-api-query-indexes.sh
```

The script prints percentile summaries, JSON query plans, database sizes, and
the V022 index size. It owns an exact labeled tmpfs container and removes it on
success, failure, or interruption.

## Limits

This is a warm-cache synthetic query benchmark. The measured index size and
latency cannot be extrapolated directly to the monthly 200-million-row data
distribution. Full-data storage sizing, index-build duration, import impact,
and cold I/O remain pre-production checks.
