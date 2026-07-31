// Package manifest implements the language-neutral OpenDiscogs import identity contract.
package manifest

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
)

const preamble = "open-discogs-manifest/v1\n"

var checksumPattern = regexp.MustCompile(`^[0-9A-Fa-f]{64}$`)

var knownEntityTypes = map[string]struct{}{
	"artist":  {},
	"label":   {},
	"master":  {},
	"release": {},
}

// Dump identifies the content of one dated Discogs entity dump.
type Dump struct {
	EntityType     string
	DumpDate       time.Time
	ChecksumSHA256 string
}

// Fingerprint returns the manifest v1 SHA-256 fingerprint.
func Fingerprint(dumps []Dump) (string, error) {
	canonical, err := Canonical(dumps)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(canonical)
	return hex.EncodeToString(sum[:]), nil
}

// Canonical returns the exact manifest v1 preimage.
func Canonical(dumps []Dump) ([]byte, error) {
	if len(dumps) == 0 {
		return nil, errors.New("manifest must contain at least one dump")
	}

	normalized := make([]Dump, len(dumps))
	seen := make(map[string]struct{}, len(dumps))
	var dumpDate string
	for index, dump := range dumps {
		entityType := strings.ToLower(dump.EntityType)
		if _, known := knownEntityTypes[entityType]; !known {
			return nil, fmt.Errorf("unknown entity type %q", dump.EntityType)
		}
		if _, duplicate := seen[entityType]; duplicate {
			return nil, fmt.Errorf("duplicate entity type %q", entityType)
		}
		seen[entityType] = struct{}{}

		date := dump.DumpDate.Format("2006-01-02")
		if dump.DumpDate.IsZero() {
			return nil, fmt.Errorf("dump date is required for %q", entityType)
		}
		if dumpDate == "" {
			dumpDate = date
		} else if dumpDate != date {
			return nil, errors.New("all dumps must use the same dump date")
		}

		if !checksumPattern.MatchString(dump.ChecksumSHA256) {
			return nil, fmt.Errorf("invalid SHA-256 for %q", entityType)
		}
		normalized[index] = Dump{
			EntityType:     entityType,
			DumpDate:       dump.DumpDate,
			ChecksumSHA256: strings.ToLower(dump.ChecksumSHA256),
		}
	}

	sort.Slice(normalized, func(left, right int) bool {
		return normalized[left].EntityType < normalized[right].EntityType
	})

	var canonical strings.Builder
	canonical.WriteString(preamble)
	for _, dump := range normalized {
		canonical.WriteString(dump.EntityType)
		canonical.WriteByte(0)
		canonical.WriteString(dump.DumpDate.Format("2006-01-02"))
		canonical.WriteByte(0)
		canonical.WriteString(dump.ChecksumSHA256)
		canonical.WriteByte('\n')
	}
	return []byte(canonical.String()), nil
}
