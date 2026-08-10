package manifest

import (
	"reflect"
	"testing"
	"time"
)

func TestOrderedEntityTypesAndLockKeys(t *testing.T) {
	t.Parallel()

	ordered, err := OrderedEntityTypes([]string{"release", "artist", "master", "artist"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(ordered, []string{"artist", "master", "release"}) {
		t.Fatalf("OrderedEntityTypes() = %v", ordered)
	}

	for entityType, expected := range map[string]int32{
		"artist": 1, "label": 2, "master": 3, "release": 4,
	} {
		actual, err := EntityLockKey(entityType)
		if err != nil {
			t.Fatal(err)
		}
		if actual != expected {
			t.Errorf("EntityLockKey(%q) = %d, want %d", entityType, actual, expected)
		}
	}
}

func TestRequiredLockEntityTypes(t *testing.T) {
	t.Parallel()

	masterLocks, err := RequiredLockEntityTypes([]string{"master"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(masterLocks, []string{"artist", "master"}) {
		t.Fatalf("RequiredLockEntityTypes(master) = %v", masterLocks)
	}

	releaseLocks, err := RequiredLockEntityTypes([]string{"label", "release"})
	if err != nil {
		t.Fatal(err)
	}
	expected := []string{"artist", "label", "master", "release"}
	if !reflect.DeepEqual(releaseLocks, expected) {
		t.Fatalf("RequiredLockEntityTypes(label, release) = %v", releaseLocks)
	}

	if _, err := RequiredLockEntityTypes([]string{"unknown"}); err == nil {
		t.Fatal("unknown entity type was accepted")
	}
}

func TestIsDowngrade(t *testing.T) {
	t.Parallel()

	checkpoint := time.Date(2026, time.July, 1, 0, 0, 0, 0, time.UTC)
	if !IsDowngrade(checkpoint.AddDate(0, -1, 0), checkpoint) {
		t.Fatal("older candidate was not a downgrade")
	}
	if IsDowngrade(checkpoint, checkpoint) {
		t.Fatal("same date was a downgrade")
	}
	if IsDowngrade(checkpoint.AddDate(0, 1, 0), checkpoint) {
		t.Fatal("newer candidate was a downgrade")
	}
}
