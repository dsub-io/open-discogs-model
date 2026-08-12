package schema

import (
	"bytes"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"strings"
	"testing"
	"testing/fstest"
)

var errInjectedFileSystem = errors.New("injected filesystem failure")

type failingFS struct{}

func (failingFS) Open(string) (fs.File, error) {
	return nil, errInjectedFileSystem
}

type selectiveFailureFS struct {
	files    fs.FS
	failName string
}

func (filesystem selectiveFailureFS) Open(name string) (fs.File, error) {
	if name == filesystem.failName {
		return nil, errInjectedFileSystem
	}
	return filesystem.files.Open(name)
}

func TestLegacyLiquibaseCompatibilityPackageResources(t *testing.T) {
	t.Parallel()

	manifest, err := LegacyLiquibaseCompatibility()
	if err != nil {
		t.Fatalf("LegacyLiquibaseCompatibility() error = %v", err)
	}
	if len(manifest.Migrations) != legacyLiquibaseMigrationCount {
		t.Fatalf("migration count = %d, want %d", len(manifest.Migrations), legacyLiquibaseMigrationCount)
	}
	if _, err := Migrations(); err != nil {
		t.Fatalf("Migrations() error = %v", err)
	}

	resourceNames := []string{
		LegacyLiquibaseManifestResource,
		LegacyLiquibaseSchemaResource,
		LegacySchemaFingerprintResource,
	}
	for _, resourceName := range resourceNames {
		packaged, resourceErr := LegacyLiquibaseContract(resourceName)
		if resourceErr != nil {
			t.Fatalf("LegacyLiquibaseContract(%q) error = %v", resourceName, resourceErr)
		}
		disk, readErr := os.ReadFile("contracts/" + resourceName)
		if readErr != nil {
			t.Fatalf("ReadFile(%q) error = %v", resourceName, readErr)
		}
		if !bytes.Equal(packaged, disk) {
			t.Errorf("packaged resource %q differs from schema/contracts", resourceName)
		}
		if len(packaged) == 0 {
			t.Errorf("packaged resource %q is empty", resourceName)
		}
		packaged[0] ^= 0xff
		again, secondErr := LegacyLiquibaseContract(resourceName)
		if secondErr != nil {
			t.Fatalf("second LegacyLiquibaseContract(%q) error = %v", resourceName, secondErr)
		}
		if bytes.Equal(packaged, again) {
			t.Errorf("LegacyLiquibaseContract(%q) returned shared mutable bytes", resourceName)
		}
	}
	if _, err := LegacyLiquibaseContract("unknown.json"); err == nil {
		t.Error("LegacyLiquibaseContract() accepted an unknown resource")
	}
	if !json.Valid(mustContract(t, LegacyLiquibaseManifestResource)) {
		t.Error("packaged legacy manifest is not valid JSON")
	}
	if !json.Valid(mustContract(t, LegacyLiquibaseSchemaResource)) {
		t.Error("packaged legacy JSON schema is not valid JSON")
	}
	verifier := string(mustContract(t, LegacySchemaFingerprintResource))
	if !strings.Contains(verifier, "current_schema()") || !strings.Contains(verifier, "fingerprint_input") {
		t.Error("packaged fingerprint verifier does not expose the documented SQL contract")
	}
}

func TestLegacyLiquibaseCompatibilityLookups(t *testing.T) {
	t.Parallel()

	manifest := mustManifest(t)
	contract, found := manifest.SchemaContract("V007")
	if !found || contract.Prefix != "V007" {
		t.Fatalf("SchemaContract(V007) = %#v, %t", contract, found)
	}
	if _, found := manifest.SchemaContract("V999"); found {
		t.Error("SchemaContract(V999) unexpectedly succeeded")
	}
	fingerprint, found := contract.ExpectedFingerprint(18)
	if !found || fingerprint != "833cdf351ec53874c1cc244578e3aac2e0b87bcb68f8228b0d4286977d190d13" {
		t.Fatalf("ExpectedFingerprint(18) = %q, %t", fingerprint, found)
	}
	if _, found := contract.ExpectedFingerprint(19); found {
		t.Error("ExpectedFingerprint(19) unexpectedly succeeded")
	}
	policy, found := manifest.Migrations[0].LegacyChangeSets[0].ExecutionPolicy(
		LegacyExecutionTypeMarkRan,
	)
	if !found || policy.AdoptionProof != LegacyAdoptionProofSchemaContract {
		t.Fatalf("ExecutionPolicy(MARK_RAN) = %#v, %t", policy, found)
	}
	if _, found := manifest.Migrations[0].LegacyChangeSets[0].ExecutionPolicy("FAILED"); found {
		t.Error("ExecutionPolicy(FAILED) unexpectedly succeeded")
	}
}

func TestPrefixedFS(t *testing.T) {
	t.Parallel()

	rooted := prefixedFS{
		files: fstest.MapFS{
			"root/value.txt": &fstest.MapFile{Data: []byte("value")},
		},
		prefix: "root",
	}
	value, err := fs.ReadFile(rooted, "value.txt")
	if err != nil || string(value) != "value" {
		t.Fatalf("ReadFile() = %q, %v", value, err)
	}
	if _, err := rooted.Open("../value.txt"); !errors.Is(err, fs.ErrInvalid) {
		t.Fatalf("Open(invalid) error = %v, want fs.ErrInvalid", err)
	}
}

func TestParseLegacyLiquibaseManifestRejectsJSONErrors(t *testing.T) {
	t.Parallel()

	valid := mustContract(t, LegacyLiquibaseManifestResource)
	unknown := bytes.Replace(valid, []byte("\"formatVersion\": 1,"), []byte("\"unknown\": true, \"formatVersion\": 1,"), 1)
	cases := []struct {
		name string
		data []byte
	}{
		{name: "invalid document", data: []byte("{")},
		{name: "unknown field", data: unknown},
		{name: "trailing value", data: append(bytes.Clone(valid), []byte("\n{}")...)},
		{name: "invalid trailer", data: append(bytes.Clone(valid), []byte("\n]")...)},
	}
	for _, testCase := range cases {
		testCase := testCase
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			if _, err := ParseLegacyLiquibaseManifest(
				testCase.data,
				validMigrationFS(t),
				validContractFS(t),
			); err == nil {
				t.Error("ParseLegacyLiquibaseManifest() unexpectedly succeeded")
			}
		})
	}
}

func TestParseLegacyLiquibaseManifestRequiresFilesystems(t *testing.T) {
	t.Parallel()

	manifest := mustContract(t, LegacyLiquibaseManifestResource)
	if _, err := ParseLegacyLiquibaseManifest(manifest, nil, validContractFS(t)); err == nil {
		t.Error("ParseLegacyLiquibaseManifest() accepted a nil migration filesystem")
	}
	if _, err := ParseLegacyLiquibaseManifest(manifest, validMigrationFS(t), nil); err == nil {
		t.Error("ParseLegacyLiquibaseManifest() accepted a nil contract filesystem")
	}
}

func TestValidCanonicalMigrationFilename(t *testing.T) {
	t.Parallel()

	cases := []struct {
		filename string
		valid    bool
	}{
		{filename: "V001__initial_schema.sql", valid: true},
		{filename: "V001_initial_schema.sql", valid: false},
		{filename: "V001__.sql", valid: false},
		{filename: "V001__Initial_schema.sql", valid: false},
		{filename: "V001__initial-schema.sql", valid: false},
	}
	for _, testCase := range cases {
		if got := validCanonicalMigrationFilename(testCase.filename, "V001"); got != testCase.valid {
			t.Errorf("validCanonicalMigrationFilename(%q) = %t, want %t", testCase.filename, got, testCase.valid)
		}
	}
}

func TestLegacyLiquibaseManifestRejectsMetadataAndContractDrift(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name   string
		mutate func(*LegacyLiquibaseManifest)
	}{
		{name: "format version", mutate: func(value *LegacyLiquibaseManifest) { value.FormatVersion = 2 }},
		{name: "contract", mutate: func(value *LegacyLiquibaseManifest) { value.Contract = "other" }},
		{name: "Liquibase version", mutate: func(value *LegacyLiquibaseManifest) { value.LiquibaseVersion = "5.0.4" }},
		{name: "checksum version", mutate: func(value *LegacyLiquibaseManifest) { value.LiquibaseChecksumVersion = 8 }},
		{name: "schema resource name", mutate: func(value *LegacyLiquibaseManifest) { value.SchemaDefinition.Name = "other.json" }},
		{name: "schema resource checksum length", mutate: func(value *LegacyLiquibaseManifest) { value.SchemaDefinition.SHA256 = "0" }},
		{name: "schema resource checksum uppercase", mutate: func(value *LegacyLiquibaseManifest) { value.SchemaDefinition.SHA256 = strings.Repeat("A", 64) }},
		{name: "schema resource checksum nonhex", mutate: func(value *LegacyLiquibaseManifest) { value.SchemaDefinition.SHA256 = strings.Repeat("g", 64) }},
		{name: "schema resource checksum mismatch", mutate: func(value *LegacyLiquibaseManifest) { value.SchemaDefinition.SHA256 = strings.Repeat("0", 64) }},
		{name: "schema contract count", mutate: func(value *LegacyLiquibaseManifest) { value.SchemaContracts = value.SchemaContracts[:2] }},
		{name: "schema contract prefix", mutate: func(value *LegacyLiquibaseManifest) { value.SchemaContracts[0].Prefix = "V005" }},
		{name: "schema contract migration count", mutate: func(value *LegacyLiquibaseManifest) {
			value.SchemaContracts[0].MigrationVersions = value.SchemaContracts[0].MigrationVersions[:3]
		}},
		{name: "schema contract migration order", mutate: func(value *LegacyLiquibaseManifest) { value.SchemaContracts[0].MigrationVersions[0] = "V002" }},
		{name: "schema contract verifier name", mutate: func(value *LegacyLiquibaseManifest) { value.SchemaContracts[0].Verifier.Name = "other.sql" }},
		{name: "schema contract verifier mismatch", mutate: func(value *LegacyLiquibaseManifest) {
			value.SchemaContracts[0].Verifier.SHA256 = strings.Repeat("0", 64)
		}},
		{name: "fingerprint count", mutate: func(value *LegacyLiquibaseManifest) {
			value.SchemaContracts[0].ExpectedFingerprints = value.SchemaContracts[0].ExpectedFingerprints[:3]
		}},
		{name: "fingerprint major", mutate: func(value *LegacyLiquibaseManifest) {
			value.SchemaContracts[0].ExpectedFingerprints[0].PostgreSQLMajor = 14
		}},
		{name: "fingerprint checksum", mutate: func(value *LegacyLiquibaseManifest) {
			value.SchemaContracts[0].ExpectedFingerprints[0].SHA256 = "invalid"
		}},
	}
	for _, testCase := range cases {
		testCase := testCase
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			manifest := cloneManifest(t, mustManifest(t))
			testCase.mutate(&manifest)
			assertManifestRejected(t, manifest, validMigrationFS(t), validContractFS(t))
		})
	}
}

func TestLegacyLiquibaseManifestRejectsMissingContractResources(t *testing.T) {
	t.Parallel()

	manifest := mustManifest(t)
	contracts := validContractFS(t)
	delete(contracts, LegacyLiquibaseSchemaResource)
	assertManifestRejected(t, manifest, validMigrationFS(t), contracts)
}

func TestLegacyLiquibaseManifestRejectsMigrationDrift(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name   string
		mutate func(*LegacyLiquibaseManifest)
	}{
		{name: "migration count", mutate: func(value *LegacyLiquibaseManifest) { value.Migrations = value.Migrations[:6] }},
		{name: "migration version", mutate: func(value *LegacyLiquibaseManifest) { value.Migrations[0].Version = "V002" }},
		{name: "migration filename", mutate: func(value *LegacyLiquibaseManifest) { value.Migrations[0].CanonicalFilename = "V001.sql" }},
		{name: "canonical checksum length", mutate: func(value *LegacyLiquibaseManifest) { value.Migrations[0].CanonicalSHA256 = "0" }},
		{name: "duplicate canonical checksum", mutate: func(value *LegacyLiquibaseManifest) {
			value.Migrations[1].CanonicalSHA256 = value.Migrations[0].CanonicalSHA256
		}},
		{name: "canonical checksum mismatch", mutate: func(value *LegacyLiquibaseManifest) { value.Migrations[0].CanonicalSHA256 = strings.Repeat("0", 64) }},
		{name: "changeset count", mutate: func(value *LegacyLiquibaseManifest) {
			value.Migrations[0].LegacyChangeSets = value.Migrations[0].LegacyChangeSets[:1]
		}},
		{name: "schema mode enum", mutate: func(value *LegacyLiquibaseManifest) { value.Migrations[0].LegacyChangeSets[0].SchemaMode = "UNKNOWN" }},
		{name: "identity", mutate: func(value *LegacyLiquibaseManifest) { value.Migrations[0].LegacyChangeSets[0].Author = "other" }},
		{name: "checksum policy enum", mutate: func(value *LegacyLiquibaseManifest) {
			value.Migrations[0].LegacyChangeSets[0].ChecksumPolicy = "UNKNOWN"
		}},
		{name: "public checksum format", mutate: func(value *LegacyLiquibaseManifest) {
			value.Migrations[0].LegacyChangeSets[0].Checksum = "8:21b43c01c07539940ef584360151932e"
		}},
		{name: "public checksum value", mutate: func(value *LegacyLiquibaseManifest) {
			value.Migrations[0].LegacyChangeSets[0].Checksum = "9:00000000000000000000000000000000"
		}},
		{name: "custom checksum", mutate: func(value *LegacyLiquibaseManifest) {
			value.Migrations[0].LegacyChangeSets[1].Checksum = "9:00000000000000000000000000000000"
		}},
		{name: "execution policy count", mutate: func(value *LegacyLiquibaseManifest) {
			value.Migrations[0].LegacyChangeSets[0].ExecutionPolicies = value.Migrations[0].LegacyChangeSets[0].ExecutionPolicies[:1]
		}},
		{name: "execution type enum", mutate: func(value *LegacyLiquibaseManifest) {
			value.Migrations[0].LegacyChangeSets[0].ExecutionPolicies[0].ExecutionType = "FAILED"
		}},
		{name: "adoption proof enum", mutate: func(value *LegacyLiquibaseManifest) {
			value.Migrations[0].LegacyChangeSets[0].ExecutionPolicies[0].AdoptionProof = "UNKNOWN"
		}},
	}
	for _, testCase := range cases {
		testCase := testCase
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			manifest := cloneManifest(t, mustManifest(t))
			testCase.mutate(&manifest)
			assertManifestRejected(t, manifest, validMigrationFS(t), validContractFS(t))
		})
	}
}

func TestLegacyLiquibaseManifestRejectsMigrationInventoryFailures(t *testing.T) {
	t.Parallel()

	manifest := mustManifest(t)
	assertManifestRejected(t, manifest, failingFS{}, validContractFS(t))

	shortInventory := validMigrationFS(t)
	delete(shortInventory, manifest.Migrations[6].CanonicalFilename)
	assertManifestRejected(t, manifest, shortInventory, validContractFS(t))

	wrongInventory := validMigrationFS(t)
	delete(wrongInventory, manifest.Migrations[0].CanonicalFilename)
	wrongInventory["A000__wrong.sql"] = &fstest.MapFile{Data: []byte("wrong")}
	assertManifestRejected(t, manifest, wrongInventory, validContractFS(t))

	directoryInventory := validMigrationFS(t)
	directoryInventory[manifest.Migrations[0].CanonicalFilename] = &fstest.MapFile{Mode: fs.ModeDir}
	assertManifestRejected(t, manifest, directoryInventory, validContractFS(t))

	readFailure := selectiveFailureFS{
		files:    validMigrationFS(t),
		failName: manifest.Migrations[0].CanonicalFilename,
	}
	assertManifestRejected(t, manifest, readFailure, validContractFS(t))

	invalidFilenameManifest := cloneManifest(t, manifest)
	originalFilename := invalidFilenameManifest.Migrations[0].CanonicalFilename
	invalidFilenameManifest.Migrations[0].CanonicalFilename = "V001__initial_schema.txt"
	invalidFilenameInventory := validMigrationFS(t)
	invalidFilenameInventory[invalidFilenameManifest.Migrations[0].CanonicalFilename] =
		invalidFilenameInventory[originalFilename]
	delete(invalidFilenameInventory, originalFilename)
	assertManifestRejected(
		t,
		invalidFilenameManifest,
		invalidFilenameInventory,
		validContractFS(t),
	)
}

func mustManifest(t *testing.T) LegacyLiquibaseManifest {
	t.Helper()
	manifest, err := LegacyLiquibaseCompatibility()
	if err != nil {
		t.Fatalf("LegacyLiquibaseCompatibility() error = %v", err)
	}
	return manifest
}

func cloneManifest(t *testing.T, source LegacyLiquibaseManifest) LegacyLiquibaseManifest {
	t.Helper()
	encoded, err := json.Marshal(source)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	var clone LegacyLiquibaseManifest
	if err := json.Unmarshal(encoded, &clone); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	return clone
}

func assertManifestRejected(
	t *testing.T,
	manifest LegacyLiquibaseManifest,
	migrations fs.FS,
	contracts fs.FS,
) {
	t.Helper()
	encoded, err := json.Marshal(manifest)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	if _, err := ParseLegacyLiquibaseManifest(encoded, migrations, contracts); err == nil {
		t.Error("ParseLegacyLiquibaseManifest() unexpectedly succeeded")
	}
}

func validMigrationFS(t *testing.T) fstest.MapFS {
	t.Helper()
	manifest := mustManifest(t)
	migrations := make(fstest.MapFS, len(manifest.Migrations))
	for _, migration := range manifest.Migrations {
		content, err := migrationFiles.ReadFile("migrations/" + migration.CanonicalFilename)
		if err != nil {
			t.Fatalf("ReadFile(%q) error = %v", migration.CanonicalFilename, err)
		}
		migrations[migration.CanonicalFilename] = &fstest.MapFile{Data: bytes.Clone(content)}
	}
	return migrations
}

func validContractFS(t *testing.T) fstest.MapFS {
	t.Helper()
	contracts := make(fstest.MapFS, 2)
	for _, name := range []string{LegacyLiquibaseSchemaResource, LegacySchemaFingerprintResource} {
		contracts[name] = &fstest.MapFile{Data: mustContract(t, name)}
	}
	return contracts
}

func mustContract(t *testing.T, name string) []byte {
	t.Helper()
	content, err := LegacyLiquibaseContract(name)
	if err != nil {
		t.Fatalf("LegacyLiquibaseContract(%q) error = %v", name, err)
	}
	return content
}
