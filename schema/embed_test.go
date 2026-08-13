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
		"V017__artist_alias_ordinal.sql",
		"V018__artist_group_ordinal.sql",
		"V019__artist_member_ordinal.sql",
		"V020__artist_name_variation_ordinal.sql",
		"V021__artist_url_ordinal.sql",
		"V022__label_sub_label_ordinal.sql",
		"V023__label_url_ordinal.sql",
		"V024__master_artist_ordinal.sql",
		"V025__master_genre_ordinal.sql",
		"V026__master_style_ordinal.sql",
		"V027__master_video_ordinal.sql",
		"V028__label_release_item_ordinal.sql",
		"V029__release_item_artist_ordinal.sql",
		"V030__release_item_credited_artist_ordinal.sql",
		"V031__release_item_format_ordinal.sql",
		"V032__release_item_genre_ordinal.sql",
		"V033__release_item_identifier_ordinal.sql",
		"V034__release_item_image_ordinal.sql",
		"V035__release_item_style_ordinal.sql",
		"V036__release_item_track_ordinal.sql",
		"V037__release_item_video_ordinal.sql",
		"V038__release_item_work_ordinal.sql",
		"V039__remove_relation_created_at.sql",
		"V040__catalog_readiness_state.sql",
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
