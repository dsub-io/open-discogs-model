package model

import (
	"testing"
	"time"
)

func TestTableNames(t *testing.T) {
	t.Parallel()

	if len(TableNames) != 33 {
		t.Fatalf("table count = %d, want 33", len(TableNames))
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
		"discogs_import_run_chunk",
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

func TestImportProgressModels(t *testing.T) {
	t.Parallel()

	resumedFromRunID := int64(11)
	chunkSize := int64(5)
	totalItems := int64(14)
	totalChunks := int64(3)
	progressedAt := time.Date(2026, time.August, 10, 0, 0, 0, 0, time.UTC)
	run := DiscogsImportRun{ResumedFromRunID: &resumedFromRunID}
	dump := DiscogsImportRunDump{
		ImportRunID: 12, EntityType: "release", DumpID: 13,
		ProcessedItems: 14, LastProgressAt: &progressedAt, CompletedAt: &progressedAt,
		ChunkSize: &chunkSize, TotalItems: &totalItems, TotalChunks: &totalChunks,
	}
	chunk := DiscogsImportRunChunk{
		ImportRunID: 12, EntityType: "release", ChunkIndex: 2,
		FirstItemIndex: 10, ItemCount: 4, CompletedAt: progressedAt,
	}
	checkpoint := DiscogsImportCheckpoint{ResumedFromRunID: &resumedFromRunID}

	if run.ResumedFromRunID == nil || *run.ResumedFromRunID != resumedFromRunID {
		t.Fatalf("resumed run ID = %v", run.ResumedFromRunID)
	}
	if dump.ProcessedItems != 14 || dump.ChunkSize == nil || *dump.ChunkSize != chunkSize ||
		dump.TotalItems == nil || *dump.TotalItems != totalItems || dump.TotalChunks == nil ||
		*dump.TotalChunks != totalChunks || dump.LastProgressAt == nil || dump.CompletedAt == nil {
		t.Fatalf("import progress = %+v", dump)
	}
	if chunk.ChunkIndex != 2 || chunk.FirstItemIndex != 10 || chunk.ItemCount != 4 {
		t.Fatalf("import chunk = %+v", chunk)
	}
	if checkpoint.ResumedFromRunID == nil || *checkpoint.ResumedFromRunID != resumedFromRunID {
		t.Fatalf("checkpoint resumed run ID = %v", checkpoint.ResumedFromRunID)
	}
}
