// Package schema exposes the canonical OpenDiscogs PostgreSQL migrations.
package schema

import (
	"embed"
	"io/fs"
)

// migrationFiles contains the versioned SQL migrations shipped with every
// OpenDiscogs model release.
//
//go:embed migrations/*.sql
var migrationFiles embed.FS

// Migrations returns a read-only filesystem rooted at the migrations directory.
func Migrations() (fs.FS, error) {
	return fs.Sub(migrationFiles, "migrations")
}
