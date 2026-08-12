package manifest

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

// AdvisoryLockNamespace is the first PostgreSQL advisory lock key shared by all importers.
const AdvisoryLockNamespace int32 = 1329876273

var entityLockKeys = map[string]int32{
	"artist":  1,
	"label":   2,
	"master":  3,
	"release": 4,
}

var entityImportContractRevisions = map[string]int32{
	"artist":  1,
	"label":   1,
	"master":  1,
	"release": 3,
}

var entityLockDependencies = map[string][]string{
	"artist":  {"artist"},
	"label":   {"label"},
	"master":  {"artist", "master"},
	"release": {"artist", "label", "master", "release"},
}

// EntityLockKey returns the stable second PostgreSQL advisory lock key.
func EntityLockKey(entityType string) (int32, error) {
	key, found := entityLockKeys[strings.ToLower(entityType)]
	if !found {
		return 0, fmt.Errorf("unknown entity type %q", entityType)
	}
	return key, nil
}

// ImportContractRevision returns the current stored-data semantics revision for an entity.
// Successful checkpoints are compatible across processors only at this revision; interrupted
// runs still require an exact processor name and version match.
func ImportContractRevision(entityType string) (int32, error) {
	revision, found := entityImportContractRevisions[strings.ToLower(entityType)]
	if !found {
		return 0, fmt.Errorf("unknown entity type %q", entityType)
	}
	return revision, nil
}

// OrderedEntityTypes validates, de-duplicates, and sorts entity types before lock acquisition.
func OrderedEntityTypes(entityTypes []string) ([]string, error) {
	seen := make(map[string]struct{}, len(entityTypes))
	ordered := make([]string, 0, len(entityTypes))
	for _, value := range entityTypes {
		entityType := strings.ToLower(value)
		if _, err := EntityLockKey(entityType); err != nil {
			return nil, err
		}
		if _, duplicate := seen[entityType]; duplicate {
			continue
		}
		seen[entityType] = struct{}{}
		ordered = append(ordered, entityType)
	}
	sort.Strings(ordered)
	return ordered, nil
}

// RequiredLockEntityTypes expands selected entities to every read and write dependency lock.
func RequiredLockEntityTypes(selectedEntityTypes []string) ([]string, error) {
	selected, err := OrderedEntityTypes(selectedEntityTypes)
	if err != nil {
		return nil, err
	}
	lockTypes := make([]string, 0, len(entityLockKeys))
	for _, entityType := range selected {
		lockTypes = append(lockTypes, entityLockDependencies[entityType]...)
	}
	return OrderedEntityTypes(lockTypes)
}

// IsDowngrade reports whether a candidate predates the currently applied dump.
func IsDowngrade(candidate, checkpoint time.Time) bool {
	candidateDate := candidate.Format("2006-01-02")
	checkpointDate := checkpoint.Format("2006-01-02")
	return candidateDate < checkpointDate
}
