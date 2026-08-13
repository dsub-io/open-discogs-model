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
		"V006__concurrent_import_progress.sql",
		"V007__api_query_indexes.sql",
		"V008__label_release_catalog_identity.sql",
		"V009__release_convergence_contract.sql",
		"V010__release_credited_artist_identity.sql",
		"V011__release_format_identity.sql",
		"V012__release_identifier_identity.sql",
		"V013__release_image_identity.sql",
		"V014__release_track_identity.sql",
		"V015__release_video_identity.sql",
		"V016__release_work_identity.sql",
		"V017__remove_relation_created_at.sql",
		"V018__catalog_readiness_state.sql",
		"V019__remove_relation_surrogate_ids.sql",
		"V020__bootstrap_foreign_key_finalization.sql",
		"V021__non_release_relation_identity.sql",
		"V022__release_combined_filter_index.sql",
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
