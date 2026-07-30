# OpenDiscogs jOOQ

jOOQ-generated schema classes shared by DSUB OpenDiscogs data services.

This is an independent DSUB project. It is not affiliated with or endorsed by
Discogs.

[discogs-batch](https://github.com/echovisionlab/discogs-batch)

## Dependency

Releases are published to Maven Central:

```groovy
repositories {
    mavenCentral()
}

dependencies {
    implementation 'io.dsub.opendiscogs:open-discogs-jooq:0.0.4'
}
```

## What this project contains

The PostgreSQL schema in `src/main/resources/postgresql-init.sql` is started in
an ephemeral Testcontainers database. The Gradle jOOQ task introspects that
schema and generates the Java table and record types included in the library.

## Publishing

Pushing a semantic version tag such as `v0.0.5` builds, signs, validates, and
publishes that immutable version through Maven Central. Central credentials and
the GPG private key are read only from encrypted GitHub Actions secrets; they
are not stored in this repository or Gradle configuration.

## License

Licensed under the Apache License, Version 2.0. See `LICENSE` and `NOTICE`.
