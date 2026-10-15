# Upgrading to the Go model v1

Version 1.0.0 makes Go the maintained model implementation. The Java API and
Batch repositories are archived. This release removes Java source, jOOQ
code generation, Gradle tooling, and Maven Central publication from the model
repository.

## Go consumers

TODO: Tag a model release with the new module path, then replace the retained
v1.0.0 below with that tag. Update the dependency and tidy the module only after
that release is available:

```sh
go get github.com/echovisionlab/open-discogs-model@v1.0.0
go mod tidy
```

The module path is now `github.com/echovisionlab/open-discogs-model`. Update
imports of `model`, `schema`, and `manifest` to use this owner. Go major version 1
does not add a `/v1` suffix. Go 1.27.2 is required.

The Go package APIs, generated structs, canonical V001-V023 SQL bytes, and
import contract revisions are unchanged by this release. No new SQL migration
is added. Applications still decide when to apply existing migrations and must
follow their maintenance requirements. Upgrading from an older schema still
requires applying every missing migration in order.

## Existing Java deployments

Version 1.0.0 does not publish the retired Java/jOOQ artifact
`open-discogs-model-jooq`.
Historical 0.x tags retain their Java source. Existing Java deployments should
keep their released dependencies while planning the application migration:

- [Java API to Go API](https://github.com/echovisionlab/open-discogs-api/blob/main/docs/migration-to-go.md)
- [Java Batch to Go Batch](https://github.com/echovisionlab/open-discogs-batch/blob/main/docs/migration-to-go.md)

The Go `schema` package retains the legacy Liquibase adoption manifest and
catalog fingerprint checks. Historical Java import identities and checkpoints
remain part of the compatibility contracts; removing the Java toolchain does
not remove those database migration checks.
