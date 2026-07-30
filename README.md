# OpenDiscogs jOOQ

jOOQ-generated schema classes shared by DSUB OpenDiscogs data services.

This is an independent DSUB project. It is not affiliated with or endorsed by
Discogs.

[OpenDiscogs Batch](https://github.com/dsub-io/open-discogs-batch)

## Dependency

Releases are published to Maven Central:

<!-- x-release-please-start-version -->
```groovy
repositories {
    mavenCentral()
}

dependencies {
    implementation 'io.dsub.opendiscogs:open-discogs-jooq:0.0.4'
}
```
<!-- x-release-please-end -->

The artifact exports jOOQ 3.21.6 as an API dependency. Consumers can use the
generated types under `io.dsub.opendiscogs.jooq` without declaring a separate
jOOQ version. The library and its generated classes require Java 21.

## What this project contains

The PostgreSQL schema in `src/main/resources/postgresql-init.sql` is started in
an ephemeral Testcontainers database. The Gradle jOOQ task introspects that
schema and generates the Java table and record types included in the library.
The build uses JDK 21, Gradle 9.6.1, jOOQ 3.21.6, PostgreSQL 42.7.13, and
Testcontainers 2.0.5. The official jOOQ Gradle code-generation plugin is used
instead of the former third-party plugin.

With SDKMAN installed, activate the repository's Temurin 21 toolchain and run
the complete build with:

```bash
sdk env
./gradlew clean build --warning-mode=fail
```

## Publishing

Conventional commits merged into `main` are collected by Release Please. It
opens or updates a `build: release <version>` pull request containing the
version and changelog changes. Merging that release pull request creates the
semantic version tag and GitHub Release, then the same workflow builds, signs,
validates, and publishes that immutable version through Maven Central.

There is no manual tag publishing path. Central credentials, the Release Please
token, and the GPG private key are read only from encrypted GitHub Actions
secrets; they are not stored in this repository or Gradle configuration.

## License

Licensed under the Apache License, Version 2.0. See `LICENSE` and `NOTICE`.
