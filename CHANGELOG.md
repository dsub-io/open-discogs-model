# Changelog

## [0.3.1](https://github.com/dsub-io/open-discogs-model/compare/v0.3.0...v0.3.1) (2026-08-13)


### Bug Fixes

* preserve canonical relation identities and import state ([#57](https://github.com/dsub-io/open-discogs-model/issues/57)) ([3d4b66e](https://github.com/dsub-io/open-discogs-model/commit/3d4b66e4f5394965986afc96a49b246888ed630a))

## [0.3.0](https://github.com/dsub-io/open-discogs-model/compare/v0.2.3...v0.3.0) (2026-08-12)


### Features

* add a canonical release-import convergence contract ([#49](https://github.com/dsub-io/open-discogs-model/pull/49))
  * record an explicit import-contract revision per entity (`artist=1`,
    `label=1`, `master=1`, `release=2`) so Go and Java can distinguish
    compatible checkpoints from imports created with older release semantics
  * require `master.main_release_id` to reference a release owned by that same
    master and prevent one release from being the main release of two masters
  * clear a stale main-release reference before a release moves to another
    master, allowing interrupted multi-transaction imports to converge safely


### Bug Fixes

* publish a strict legacy Liquibase adoption contract for Java releases
  `1.0.0` through `1.2.1` ([#49](https://github.com/dsub-io/open-discogs-model/pull/49))
  * bind V001-V007 history to released changeset identities, canonical SQL
    hashes, permitted execution states, and PostgreSQL schema fingerprints
  * fail closed on partial, unknown, or catalog-mismatched histories instead of
    replaying already-applied schema changes
* validate the published jOOQ dependency node against the declared Java API
  version instead of a stale hardcoded version ([#51](https://github.com/dsub-io/open-discogs-model/pull/51))
* wait for the final PostgreSQL server instead of the temporary initialization
  server in release contract tests ([#53](https://github.com/dsub-io/open-discogs-model/pull/53))

### Verification

* PostgreSQL 15.13 and 18.4 integration tests cover clean V009 application,
  rollback on invalid existing relationships, and interrupted A-to-B master
  reassignment convergence
* Go race and vet checks, the Gradle Java build, packaged migration inventory,
  and test-created Docker resource cleanup all passed

### Upgrade notes

* V009 validates existing data while adding unique constraints, a composite
  foreign key, and a trigger; mismatched or duplicate relationships abort the
  migration without a partial schema change
* production-scale index-build duration, lock time, and temporary disk usage
  have not been measured; operators should measure them on a production-sized
  copy and schedule a backed-up maintenance window before upgrading

## [0.2.3](https://github.com/dsub-io/open-discogs-model/compare/v0.2.2...v0.2.3) (2026-08-12)


### Bug Fixes

* preserve distinct catalog numbers on repeated release-label credits and verify upgrades from V007 ([#46](https://github.com/dsub-io/open-discogs-model/pull/46))

## [0.2.2](https://github.com/dsub-io/open-discogs-model/compare/v0.2.1...v0.2.2) (2026-08-11)


### Performance Improvements

* add indexed API query paths ([#44](https://github.com/dsub-io/open-discogs-model/issues/44)) ([85c43ad](https://github.com/dsub-io/open-discogs-model/commit/85c43ad062ed273c856cbc2ab6246f22280aef64))
  * release-title substring p95 fell from 194.535 ms to 0.136 ms (99.930%)
    and artist-release lookup p95 fell from 17.309 ms to 0.061 ms (99.648%)
    in the reproducible 1,000,000-release synthetic benchmark
  * canonical indexes added 164.1 MiB (54.7%) to that synthetic database;
    full-dump storage, import duration, cold I/O, and concurrency remain
    pre-production validation gates

## [0.2.1](https://github.com/dsub-io/open-discogs-model/compare/v0.2.0...v0.2.1) (2026-08-10)


### Bug Fixes

* lock import reference dependencies ([#41](https://github.com/dsub-io/open-discogs-model/issues/41)) ([4bf7cc6](https://github.com/dsub-io/open-discogs-model/commit/4bf7cc6533da6bc05e6c945ae7876a7d12b0ec3a))

## [0.2.0](https://github.com/dsub-io/open-discogs-model/compare/v0.1.2...v0.2.0) (2026-08-10)


### Features

* add durable import progress ([#37](https://github.com/dsub-io/open-discogs-model/issues/37)) ([a953983](https://github.com/dsub-io/open-discogs-model/commit/a95398312e5e2898d49314c590abe89c1ca4e734))


### Bug Fixes

* make import progress concurrency-safe ([#39](https://github.com/dsub-io/open-discogs-model/issues/39)) ([47f58cd](https://github.com/dsub-io/open-discogs-model/commit/47f58cd0099df7f0b44dd76a2de7363fa192db66))

## [0.1.2](https://github.com/dsub-io/open-discogs-model/compare/v0.1.1...v0.1.2) (2026-07-31)


### Bug Fixes

* allow independent entity dump dates ([2eea8d0](https://github.com/dsub-io/open-discogs-model/commit/2eea8d055328ea1fd25bae753df64abb6d606600))

## [0.1.1](https://github.com/dsub-io/open-discogs-model/compare/v0.1.0...v0.1.1) (2026-07-31)


### Bug Fixes

* allow reissued dump paths ([7c5eec2](https://github.com/dsub-io/open-discogs-model/commit/7c5eec210f9e2cf543684da79fbddc01b79625bc))

## [0.1.0](https://github.com/dsub-io/open-discogs-model/compare/v0.0.5...v0.1.0) (2026-07-31)


### Features

* publish shared Java and Go models ([3c3332d](https://github.com/dsub-io/open-discogs-model/commit/3c3332db8ace2a34bb8d89e554ade421793a1b84))

## [0.0.5](https://github.com/dsub-io/open-discogs-model/compare/v0.0.4...v0.0.5) (2026-07-30)


### Build System

* housekeeping ([9fd860a](https://github.com/dsub-io/open-discogs-model/commit/9fd860a21283a0b645555a0cbe2ba5909767b109))
* sign automated releases ([db590ba](https://github.com/dsub-io/open-discogs-model/commit/db590ba7054f1aea397f020a1b2388f377bf3a0c))


### Maintenance

* update repository ownership metadata ([bf02db3](https://github.com/dsub-io/open-discogs-model/commit/bf02db3ea5372786da95062d7af44b9e3fb7e950))


### Bug Fixes

* sign automated releases ([9f89b4e](https://github.com/dsub-io/open-discogs-model/commit/9f89b4ee372351a073d743e8a4e9c4434ac5b252))
