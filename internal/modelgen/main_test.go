package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestExportedName(t *testing.T) {
	t.Parallel()

	tests := map[string]string{
		"artist_id":       "ArtistID",
		"checksum_sha256": "ChecksumSHA256",
		"created_at":      "CreatedAt",
		"etag":            "ETag",
		"release_item":    "ReleaseItem",
		"resource_url":    "ResourceURL",
		"uri":             "URI",
	}
	for input, want := range tests {
		if got := exportedName(input); got != want {
			t.Errorf("exportedName(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestColumnType(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		column column
		want   string
	}{
		{name: "integer", column: column{dataType: "integer"}, want: "int32"},
		{
			name: "nullable SHA-256 digest",
			column: column{
				name: "identity_sha256", dataType: "bytea", nullable: true,
			},
			want: "*SHA256Digest",
		},
		{name: "nullable text", column: column{dataType: "text", nullable: true}, want: "*string"},
		{name: "timestamp", column: column{dataType: "timestamp without time zone"}, want: "time.Time"},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			got, err := columnType(test.column)
			if err != nil {
				t.Fatalf("columnType() error = %v", err)
			}
			if got != test.want {
				t.Errorf("columnType() = %q, want %q", got, test.want)
			}
		})
	}

	if _, err := columnType(column{dataType: "jsonb"}); err == nil {
		t.Error("columnType() accepted unsupported jsonb")
	}
	if _, err := columnType(column{name: "payload", dataType: "bytea"}); err == nil {
		t.Error("columnType() accepted ambiguous bytea")
	}
}

func TestReadCatalogAndGenerate(t *testing.T) {
	t.Parallel()

	input := strings.Join([]string{
		"example\tid\tbigint\tint8\tNO\tnextval('example_id_seq'::regclass)\ttrue\ttrue",
		"example\tlabel\tcharacter varying\tvarchar\tYES\t\tfalse\tfalse",
		"example\tidentity_sha256\tbytea\tbytea\tYES\t\tfalse\tfalse",
	}, "\n")
	path := filepath.Join(t.TempDir(), "catalog.tsv")
	if err := os.WriteFile(path, []byte(input), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	tables, err := readCatalog(path)
	if err != nil {
		t.Fatalf("readCatalog() error = %v", err)
	}
	source, err := generate(tables)
	if err != nil {
		t.Fatalf("generate() error = %v", err)
	}

	generated := string(source)
	for _, want := range []string{
		"type Example struct",
		`gorm:"column:id;primaryKey;autoIncrement"`,
		"func (Example) TableName() string",
	} {
		if !strings.Contains(generated, want) {
			t.Errorf("generated source does not contain %q", want)
		}
	}
	for _, want := range []string{
		`\bID\s+int64\b`,
		`\bLabel\s+\*string\b`,
		`\bIdentitySHA256\s+\*SHA256Digest\b`,
	} {
		if !regexp.MustCompile(want).MatchString(generated) {
			t.Errorf("generated source does not match %q", want)
		}
	}
}
