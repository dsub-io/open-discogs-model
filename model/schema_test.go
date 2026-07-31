package model

import "testing"

func TestTableNames(t *testing.T) {
	t.Parallel()

	if len(TableNames) != 32 {
		t.Fatalf("table count = %d, want 32", len(TableNames))
	}

	seen := make(map[string]struct{}, len(TableNames))
	for _, name := range TableNames {
		if _, exists := seen[name]; exists {
			t.Errorf("duplicate table name %q", name)
		}
		seen[name] = struct{}{}
	}

	for _, required := range []string{
		"artist",
		"discogs_dump",
		"discogs_import_checkpoint",
		"discogs_import_run",
		"discogs_import_run_dump",
		"label",
		"master",
		"release_item",
	} {
		if _, exists := seen[required]; !exists {
			t.Errorf("required table %q is missing", required)
		}
	}
}
