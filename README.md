# discogs-jooq
[![Build Status](https://app.travis-ci.com/state303/discogs-jooq.svg?branch=main)](https://app.travis-ci.com/state303/discogs-jooq)

jOOQ-generated schema classes shared by Discogs data services.

[discogs-batch](https://github.com/state303/discogs-batch)

## Dependency

Releases are published to Maven Central:

```groovy
repositories {
    mavenCentral()
}

dependencies {
    implementation 'io.dsub.discogs:discogs-jooq:0.0.4'
}
```

## What this project contains

The PostgreSQL schema in `src/main/resources/postgresql-init.sql` is started in
an ephemeral Testcontainers database. The Gradle jOOQ task introspects that
schema and generates the Java table and record types included in the library.

## License

Licensed under the Apache License, Version 2.0. See `LICENSE` and `NOTICE`.
