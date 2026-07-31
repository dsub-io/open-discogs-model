package manifest

import (
	"bufio"
	"os"
	"strings"
	"testing"
	"time"
)

func TestFingerprintMatchesSharedConformanceVector(t *testing.T) {
	t.Parallel()

	file, err := os.Open("../schema/contracts/import-manifest-v1.tsv")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = file.Close() }()

	var expected string
	var dumps []Dump
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) == 0 || strings.HasPrefix(fields[0], "#") {
			continue
		}
		if fields[0] == "expected_sha256" {
			expected = fields[1]
			continue
		}
		date, parseErr := time.Parse("2006-01-02", fields[1])
		if parseErr != nil {
			t.Fatal(parseErr)
		}
		dumps = append(dumps, Dump{
			EntityType:     fields[0],
			DumpDate:       date,
			ChecksumSHA256: fields[2],
		})
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}

	fingerprint, err := Fingerprint([]Dump{dumps[3], dumps[1], dumps[0], dumps[2]})
	if err != nil {
		t.Fatal(err)
	}
	if fingerprint != expected {
		t.Fatalf("Fingerprint() = %q, want %q", fingerprint, expected)
	}
}

func TestCanonicalRejectsAmbiguousManifests(t *testing.T) {
	t.Parallel()

	date := time.Date(2026, time.July, 1, 0, 0, 0, 0, time.UTC)
	valid := Dump{
		EntityType:     "artist",
		DumpDate:       date,
		ChecksumSHA256: strings.Repeat("a", 64),
	}
	tests := map[string][]Dump{
		"empty":          nil,
		"duplicate type": {valid, valid},
		"invalid checksum": {{
			EntityType:     "artist",
			DumpDate:       date,
			ChecksumSHA256: "not-a-checksum",
		}},
		"unknown type": {{
			EntityType:     "unknown",
			DumpDate:       date,
			ChecksumSHA256: strings.Repeat("a", 64),
		}},
	}

	for name, dumps := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if _, err := Canonical(dumps); err == nil {
				t.Fatal("Canonical() error = nil")
			}
		})
	}
}

func TestCanonicalAllowsIndependentEntityDates(t *testing.T) {
	t.Parallel()

	canonical, err := Canonical([]Dump{
		{
			EntityType:     "release",
			DumpDate:       time.Date(2026, time.July, 2, 0, 0, 0, 0, time.UTC),
			ChecksumSHA256: strings.Repeat("b", 64),
		},
		{
			EntityType:     "artist",
			DumpDate:       time.Date(2026, time.July, 1, 0, 0, 0, 0, time.UTC),
			ChecksumSHA256: strings.Repeat("a", 64),
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	want := "open-discogs-manifest/v1\n" +
		"artist\x002026-07-01\x00" + strings.Repeat("a", 64) + "\n" +
		"release\x002026-07-02\x00" + strings.Repeat("b", 64) + "\n"
	if string(canonical) != want {
		t.Fatalf("Canonical() = %q, want %q", string(canonical), want)
	}
}
