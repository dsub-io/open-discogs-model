package schema

import (
	"io/fs"
	"testing"
)

func TestMigrations(t *testing.T) {
	t.Parallel()

	migrations, err := Migrations()
	if err != nil {
		t.Fatalf("Migrations() error = %v", err)
	}

	entries, err := fs.ReadDir(migrations, ".")
	if err != nil {
		t.Fatalf("ReadDir() error = %v", err)
	}

	want := []string{
		"V001__initial_schema.sql",
		"V002__discogs_dump_catalog.sql",
		"V003__discogs_import_history.sql",
		"V004__allow_reissued_dump_paths.sql",
		"V005__durable_import_progress.sql",
	}
	if len(entries) != len(want) {
		t.Fatalf("migration count = %d, want %d", len(entries), len(want))
	}
	for index, name := range want {
		if entries[index].Name() != name {
			t.Errorf("migration[%d] = %q, want %q", index, entries[index].Name(), name)
		}
	}
}
