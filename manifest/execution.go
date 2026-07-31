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

// EntityLockKey returns the stable second PostgreSQL advisory lock key.
func EntityLockKey(entityType string) (int32, error) {
	key, found := entityLockKeys[strings.ToLower(entityType)]
	if !found {
		return 0, fmt.Errorf("unknown entity type %q", entityType)
	}
	return key, nil
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

// IsDowngrade reports whether a candidate predates the currently applied dump.
func IsDowngrade(candidate, checkpoint time.Time) bool {
	candidateDate := candidate.Format("2006-01-02")
	checkpointDate := checkpoint.Format("2006-01-02")
	return candidateDate < checkpointDate
}
