package schema

import (
	"bytes"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"path"
	"strings"
)

const (
	LegacyLiquibaseManifestResource  = "legacy-liquibase-v1.json"
	LegacyLiquibaseSchemaResource    = "legacy-liquibase-v1.schema.json"
	LegacySchemaFingerprintResource  = "legacy-schema-fingerprint-v1.sql"
	legacyLiquibaseContractID        = "open-discogs-legacy-liquibase/v1"
	legacyLiquibaseVersion           = "5.0.3"
	legacyLiquibaseChecksumVersion   = 9
	legacyLiquibaseFormatVersion     = 1
	legacyLiquibaseMigrationCount    = 7
	legacyLiquibaseAuthor            = "state303"
	legacyLiquibasePublicFilename    = "db/changelog/db.changelog-master.xml"
	legacyLiquibaseCustomFilename    = "db/changelog/db.changelog-custom-schema.xml"
	legacyLiquibaseSchemaParameter   = "databaseSchema"
	legacyMinimumPostgreSQLMajor     = 15
	legacyMaximumPostgreSQLMajor     = 18
	legacyLiquibaseChecksumPrefix    = "9:"
	legacyLiquibaseChecksumHexLength = 32
	legacyCanonicalChecksumHexLength = 64
	legacySchemaContractPrefixCount  = 3
)

var historicalPublicChecksums = [...]string{
	"9:21b43c01c07539940ef584360151932e",
	"9:1fe2b5ca5132d441129f7734864389bb",
	"9:b9d40e8e8cb0f59b0d15e764f7af4070",
	"9:c500950a7ae85ad47ea9ba14c857df39",
	"9:363a63d36fadeea4d0dc435601398341",
	"9:c89cf57ca3b13c733e9db92d2c2935a8",
	"9:f60af7da668a40343f647837995b87ec",
}

var historicalContractPrefixes = [...]int{4, 6, 7}

//go:embed contracts/legacy-liquibase-v1.json
var legacyLiquibaseManifestJSON []byte

//go:embed contracts/legacy-liquibase-v1.json contracts/legacy-liquibase-v1.schema.json contracts/legacy-schema-fingerprint-v1.sql
var legacyLiquibaseContractFiles embed.FS

// LegacySchemaMode identifies the released Liquibase changelog path.
type LegacySchemaMode string

const (
	LegacySchemaModePublic LegacySchemaMode = "PUBLIC"
	LegacySchemaModeCustom LegacySchemaMode = "CUSTOM"
)

// LegacyChecksumPolicy describes whether a historical Liquibase checksum is fixed.
type LegacyChecksumPolicy string

const (
	LegacyChecksumPolicyExact               LegacyChecksumPolicy = "EXACT"
	LegacyChecksumPolicySchemaParameterized LegacyChecksumPolicy = "SCHEMA_PARAMETERIZED"
)

// LegacyExecutionType is an execution state emitted by the released changelogs.
type LegacyExecutionType string

const (
	LegacyExecutionTypeExecuted LegacyExecutionType = "EXECUTED"
	LegacyExecutionTypeMarkRan  LegacyExecutionType = "MARK_RAN"
)

// LegacyAdoptionProof is the additional evidence required before ledger adoption.
type LegacyAdoptionProof string

const (
	LegacyAdoptionProofExactChecksum  LegacyAdoptionProof = "EXACT_CHECKSUM"
	LegacyAdoptionProofSchemaContract LegacyAdoptionProof = "SCHEMA_CONTRACT"
)

// ContractResource identifies immutable bytes packaged with the model release.
type ContractResource struct {
	Name   string `json:"name"`
	SHA256 string `json:"sha256"`
}

// LegacySchemaFingerprint binds a PostgreSQL major to a catalog fingerprint.
type LegacySchemaFingerprint struct {
	PostgreSQLMajor int    `json:"postgresMajor"`
	SHA256          string `json:"sha256"`
}

// LegacySchemaContract validates one complete historical migration prefix.
type LegacySchemaContract struct {
	Prefix               string                    `json:"prefix"`
	MigrationVersions    []string                  `json:"migrationVersions"`
	Verifier             ContractResource          `json:"verifier"`
	ExpectedFingerprints []LegacySchemaFingerprint `json:"expectedFingerprints"`
}

// LegacyExecutionPolicy defines whether a DATABASECHANGELOG state may be adopted.
type LegacyExecutionPolicy struct {
	ExecutionType LegacyExecutionType `json:"executionType"`
	AdoptionProof LegacyAdoptionProof `json:"adoptionProof"`
}

// LegacyChangeSet identifies one released Liquibase changeset representation.
type LegacyChangeSet struct {
	SchemaMode        LegacySchemaMode        `json:"schemaMode"`
	ID                string                  `json:"id"`
	Author            string                  `json:"author"`
	Filename          string                  `json:"filename"`
	ChecksumPolicy    LegacyChecksumPolicy    `json:"checksumPolicy"`
	Checksum          string                  `json:"checksum,omitempty"`
	SchemaParameter   string                  `json:"schemaParameter,omitempty"`
	ExecutionPolicies []LegacyExecutionPolicy `json:"executionPolicies"`
}

// LegacyLiquibaseMigration maps one legacy changeset to canonical SQL bytes.
type LegacyLiquibaseMigration struct {
	Version           string            `json:"version"`
	CanonicalFilename string            `json:"canonicalFilename"`
	CanonicalSHA256   string            `json:"canonicalSha256"`
	LegacyChangeSets  []LegacyChangeSet `json:"legacyChangeSets"`
}

// LegacyLiquibaseManifest is the model-owned legacy adoption contract.
type LegacyLiquibaseManifest struct {
	FormatVersion            int                        `json:"formatVersion"`
	Contract                 string                     `json:"contract"`
	SchemaDefinition         ContractResource           `json:"schemaDefinition"`
	LiquibaseVersion         string                     `json:"liquibaseVersion"`
	LiquibaseChecksumVersion int                        `json:"liquibaseChecksumVersion"`
	SchemaContracts          []LegacySchemaContract     `json:"schemaContracts"`
	Migrations               []LegacyLiquibaseMigration `json:"migrations"`
}

type prefixedFS struct {
	files  fs.FS
	prefix string
}

// LegacyLiquibaseCompatibility loads and validates the packaged v1 contract.
func LegacyLiquibaseCompatibility() (LegacyLiquibaseManifest, error) {
	return ParseLegacyLiquibaseManifest(
		legacyLiquibaseManifestJSON,
		prefixedFS{files: migrationFiles, prefix: "migrations"},
		prefixedFS{files: legacyLiquibaseContractFiles, prefix: "contracts"},
	)
}

// ParseLegacyLiquibaseManifest parses a manifest against caller-provided resources.
func ParseLegacyLiquibaseManifest(
	manifestJSON []byte,
	canonicalMigrations fs.FS,
	contractResources fs.FS,
) (LegacyLiquibaseManifest, error) {
	if canonicalMigrations == nil {
		return LegacyLiquibaseManifest{}, errors.New("canonical migration filesystem is required")
	}
	if contractResources == nil {
		return LegacyLiquibaseManifest{}, errors.New("legacy contract filesystem is required")
	}
	manifest, err := decodeLegacyLiquibaseManifest(manifestJSON)
	if err != nil {
		return LegacyLiquibaseManifest{}, err
	}
	if err := validateLegacyLiquibaseManifest(manifest, canonicalMigrations, contractResources); err != nil {
		return LegacyLiquibaseManifest{}, err
	}
	return manifest, nil
}

// LegacyLiquibaseContract returns a copy of one packaged compatibility resource.
func LegacyLiquibaseContract(name string) ([]byte, error) {
	if name != LegacyLiquibaseManifestResource &&
		name != LegacyLiquibaseSchemaResource &&
		name != LegacySchemaFingerprintResource {
		return nil, fmt.Errorf("unknown legacy Liquibase contract resource %q", name)
	}
	content, _ := fs.ReadFile(
		prefixedFS{files: legacyLiquibaseContractFiles, prefix: "contracts"},
		name,
	)
	return bytes.Clone(content), nil
}

// SchemaContract returns the exact historical prefix contract when present.
func (manifest LegacyLiquibaseManifest) SchemaContract(
	prefix string,
) (LegacySchemaContract, bool) {
	for _, contract := range manifest.SchemaContracts {
		if contract.Prefix == prefix {
			return contract, true
		}
	}
	return LegacySchemaContract{}, false
}

// ExpectedFingerprint returns the catalog fingerprint for a PostgreSQL major.
func (contract LegacySchemaContract) ExpectedFingerprint(
	postgresqlMajor int,
) (string, bool) {
	for _, fingerprint := range contract.ExpectedFingerprints {
		if fingerprint.PostgreSQLMajor == postgresqlMajor {
			return fingerprint.SHA256, true
		}
	}
	return "", false
}

// ExecutionPolicy returns the proof required for a permitted Liquibase state.
func (changeSet LegacyChangeSet) ExecutionPolicy(
	executionType LegacyExecutionType,
) (LegacyExecutionPolicy, bool) {
	for _, policy := range changeSet.ExecutionPolicies {
		if policy.ExecutionType == executionType {
			return policy, true
		}
	}
	return LegacyExecutionPolicy{}, false
}

func decodeLegacyLiquibaseManifest(data []byte) (LegacyLiquibaseManifest, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var manifest LegacyLiquibaseManifest
	if err := decoder.Decode(&manifest); err != nil {
		return LegacyLiquibaseManifest{}, fmt.Errorf("decode legacy Liquibase manifest: %w", err)
	}
	var trailing json.RawMessage
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return LegacyLiquibaseManifest{}, errors.New("decode legacy Liquibase manifest: trailing JSON value")
		}
		return LegacyLiquibaseManifest{}, fmt.Errorf("decode legacy Liquibase manifest trailer: %w", err)
	}
	return manifest, nil
}

func validateLegacyLiquibaseManifest(
	manifest LegacyLiquibaseManifest,
	canonicalMigrations fs.FS,
	contractResources fs.FS,
) error {
	if manifest.FormatVersion != legacyLiquibaseFormatVersion {
		return fmt.Errorf("legacy Liquibase format version = %d, want %d", manifest.FormatVersion, legacyLiquibaseFormatVersion)
	}
	if manifest.Contract != legacyLiquibaseContractID {
		return fmt.Errorf("legacy Liquibase contract = %q, want %q", manifest.Contract, legacyLiquibaseContractID)
	}
	if manifest.LiquibaseVersion != legacyLiquibaseVersion {
		return fmt.Errorf("legacy Liquibase version = %q, want %q", manifest.LiquibaseVersion, legacyLiquibaseVersion)
	}
	if manifest.LiquibaseChecksumVersion != legacyLiquibaseChecksumVersion {
		return fmt.Errorf("legacy Liquibase checksum version = %d, want %d", manifest.LiquibaseChecksumVersion, legacyLiquibaseChecksumVersion)
	}
	if manifest.SchemaDefinition.Name != LegacyLiquibaseSchemaResource {
		return fmt.Errorf("schema definition resource = %q, want %q", manifest.SchemaDefinition.Name, LegacyLiquibaseSchemaResource)
	}
	if err := validateContractResource(manifest.SchemaDefinition, contractResources); err != nil {
		return fmt.Errorf("validate schema definition: %w", err)
	}
	if err := validateSchemaContracts(manifest.SchemaContracts, contractResources); err != nil {
		return err
	}
	return validateLegacyMigrations(manifest.Migrations, canonicalMigrations)
}

func validateSchemaContracts(
	contracts []LegacySchemaContract,
	contractResources fs.FS,
) error {
	if len(contracts) != legacySchemaContractPrefixCount {
		return fmt.Errorf("legacy schema contract count = %d, want %d", len(contracts), legacySchemaContractPrefixCount)
	}
	for contractIndex, expectedPrefixNumber := range historicalContractPrefixes {
		contract := contracts[contractIndex]
		expectedPrefix := migrationVersion(expectedPrefixNumber)
		if contract.Prefix != expectedPrefix {
			return fmt.Errorf("legacy schema contract[%d] prefix = %q, want %q", contractIndex, contract.Prefix, expectedPrefix)
		}
		if len(contract.MigrationVersions) != expectedPrefixNumber {
			return fmt.Errorf("legacy schema contract %s migration count = %d, want %d", contract.Prefix, len(contract.MigrationVersions), expectedPrefixNumber)
		}
		for migrationIndex, version := range contract.MigrationVersions {
			expectedVersion := migrationVersion(migrationIndex + 1)
			if version != expectedVersion {
				return fmt.Errorf("legacy schema contract %s migration[%d] = %q, want %q", contract.Prefix, migrationIndex, version, expectedVersion)
			}
		}
		if contract.Verifier.Name != LegacySchemaFingerprintResource {
			return fmt.Errorf("legacy schema contract %s verifier = %q, want %q", contract.Prefix, contract.Verifier.Name, LegacySchemaFingerprintResource)
		}
		if err := validateContractResource(contract.Verifier, contractResources); err != nil {
			return fmt.Errorf("validate legacy schema contract %s verifier: %w", contract.Prefix, err)
		}
		if err := validateExpectedFingerprints(contract); err != nil {
			return err
		}
	}
	return nil
}

func validateExpectedFingerprints(contract LegacySchemaContract) error {
	expectedCount := legacyMaximumPostgreSQLMajor - legacyMinimumPostgreSQLMajor + 1
	if len(contract.ExpectedFingerprints) != expectedCount {
		return fmt.Errorf("legacy schema contract %s fingerprint count = %d, want %d", contract.Prefix, len(contract.ExpectedFingerprints), expectedCount)
	}
	for index, fingerprint := range contract.ExpectedFingerprints {
		expectedMajor := legacyMinimumPostgreSQLMajor + index
		if fingerprint.PostgreSQLMajor != expectedMajor {
			return fmt.Errorf("legacy schema contract %s PostgreSQL major[%d] = %d, want %d", contract.Prefix, index, fingerprint.PostgreSQLMajor, expectedMajor)
		}
		if !validLowerHex(fingerprint.SHA256, legacyCanonicalChecksumHexLength) {
			return fmt.Errorf("legacy schema contract %s PostgreSQL %d fingerprint is not lowercase SHA-256", contract.Prefix, fingerprint.PostgreSQLMajor)
		}
	}
	return nil
}

func validateLegacyMigrations(
	migrations []LegacyLiquibaseMigration,
	canonicalMigrations fs.FS,
) error {
	if len(migrations) != legacyLiquibaseMigrationCount {
		return fmt.Errorf("legacy migration count = %d, want %d", len(migrations), legacyLiquibaseMigrationCount)
	}
	if err := validateMigrationInventory(migrations, canonicalMigrations); err != nil {
		return err
	}
	seenCanonicalChecksums := make(map[string]struct{}, len(migrations))
	for index, migration := range migrations {
		expectedNumber := index + 1
		expectedVersion := migrationVersion(expectedNumber)
		if migration.Version != expectedVersion {
			return fmt.Errorf("legacy migration[%d] version = %q, want %q", index, migration.Version, expectedVersion)
		}
		if !validCanonicalMigrationFilename(migration.CanonicalFilename, expectedVersion) {
			return fmt.Errorf("legacy migration %s canonical filename = %q", migration.Version, migration.CanonicalFilename)
		}
		if !validLowerHex(migration.CanonicalSHA256, legacyCanonicalChecksumHexLength) {
			return fmt.Errorf("legacy migration %s canonical checksum is not lowercase SHA-256", migration.Version)
		}
		if _, duplicate := seenCanonicalChecksums[migration.CanonicalSHA256]; duplicate {
			return fmt.Errorf("duplicate canonical migration checksum %q", migration.CanonicalSHA256)
		}
		seenCanonicalChecksums[migration.CanonicalSHA256] = struct{}{}
		migrationSQL, err := fs.ReadFile(canonicalMigrations, migration.CanonicalFilename)
		if err != nil {
			return fmt.Errorf("read canonical migration %s: %w", migration.CanonicalFilename, err)
		}
		if checksum(migrationSQL) != migration.CanonicalSHA256 {
			return fmt.Errorf("canonical migration %s checksum mismatch", migration.CanonicalFilename)
		}
		if err := validateLegacyChangeSets(migration, expectedNumber); err != nil {
			return err
		}
	}
	return nil
}

func validateLegacyChangeSets(migration LegacyLiquibaseMigration, migrationNumber int) error {
	if len(migration.LegacyChangeSets) != 2 {
		return fmt.Errorf("legacy migration %s changeset count = %d, want 2", migration.Version, len(migration.LegacyChangeSets))
	}
	for index, changeSet := range migration.LegacyChangeSets {
		expectedMode := LegacySchemaModePublic
		expectedFilename := legacyLiquibasePublicFilename
		expectedChecksumPolicy := LegacyChecksumPolicyExact
		if index == 1 {
			expectedMode = LegacySchemaModeCustom
			expectedFilename = legacyLiquibaseCustomFilename
			expectedChecksumPolicy = LegacyChecksumPolicySchemaParameterized
		}
		if changeSet.SchemaMode != expectedMode {
			return fmt.Errorf("legacy migration %s changeset[%d] schema mode = %q, want %q", migration.Version, index, changeSet.SchemaMode, expectedMode)
		}
		expectedID := "open-discogs-model-" + strings.ToLower(migration.Version)
		if changeSet.ID != expectedID || changeSet.Author != legacyLiquibaseAuthor || changeSet.Filename != expectedFilename {
			return fmt.Errorf("legacy migration %s changeset[%d] identity is invalid", migration.Version, index)
		}
		if changeSet.ChecksumPolicy != expectedChecksumPolicy {
			return fmt.Errorf("legacy migration %s changeset[%d] checksum policy = %q, want %q", migration.Version, index, changeSet.ChecksumPolicy, expectedChecksumPolicy)
		}
		if expectedMode == LegacySchemaModePublic {
			if !validLiquibaseChecksum(changeSet.Checksum) {
				return fmt.Errorf("legacy migration %s public checksum format is invalid", migration.Version)
			}
			if changeSet.Checksum != historicalPublicChecksums[migrationNumber-1] || changeSet.SchemaParameter != "" {
				return fmt.Errorf("legacy migration %s public checksum contract is invalid", migration.Version)
			}
		} else if changeSet.Checksum != "" || changeSet.SchemaParameter != legacyLiquibaseSchemaParameter {
			return fmt.Errorf("legacy migration %s custom checksum contract is invalid", migration.Version)
		}
		if err := validateExecutionPolicies(migration.Version, changeSet, migrationNumber); err != nil {
			return err
		}
	}
	return nil
}

func validateExecutionPolicies(
	version string,
	changeSet LegacyChangeSet,
	migrationNumber int,
) error {
	markRanPermitted := migrationNumber == 1 || migrationNumber == 2 || migrationNumber == 3 || migrationNumber == 5 || migrationNumber == 6
	expectedCount := 1
	if markRanPermitted {
		expectedCount = 2
	}
	if len(changeSet.ExecutionPolicies) != expectedCount {
		return fmt.Errorf("legacy migration %s %s execution policy count = %d, want %d", version, changeSet.SchemaMode, len(changeSet.ExecutionPolicies), expectedCount)
	}
	for index, policy := range changeSet.ExecutionPolicies {
		expectedType := LegacyExecutionTypeExecuted
		if index == 1 {
			expectedType = LegacyExecutionTypeMarkRan
		}
		if policy.ExecutionType != expectedType {
			return fmt.Errorf("legacy migration %s %s execution policy[%d] type = %q, want %q", version, changeSet.SchemaMode, index, policy.ExecutionType, expectedType)
		}
		expectedProof := LegacyAdoptionProofSchemaContract
		if changeSet.SchemaMode == LegacySchemaModePublic && policy.ExecutionType == LegacyExecutionTypeExecuted {
			expectedProof = LegacyAdoptionProofExactChecksum
		}
		if policy.AdoptionProof != expectedProof {
			return fmt.Errorf("legacy migration %s %s %s proof = %q, want %q", version, changeSet.SchemaMode, policy.ExecutionType, policy.AdoptionProof, expectedProof)
		}
	}
	return nil
}

func validateContractResource(reference ContractResource, contractResources fs.FS) error {
	if !validLowerHex(reference.SHA256, legacyCanonicalChecksumHexLength) {
		return fmt.Errorf("contract resource %s checksum is not lowercase SHA-256", reference.Name)
	}
	content, err := fs.ReadFile(contractResources, reference.Name)
	if err != nil {
		return fmt.Errorf("read contract resource %s: %w", reference.Name, err)
	}
	if checksum(content) != reference.SHA256 {
		return fmt.Errorf("contract resource %s checksum mismatch", reference.Name)
	}
	return nil
}

func validateMigrationInventory(
	migrations []LegacyLiquibaseMigration,
	canonicalMigrations fs.FS,
) error {
	entries, err := fs.ReadDir(canonicalMigrations, ".")
	if err != nil {
		return fmt.Errorf("read canonical migration inventory: %w", err)
	}
	if len(entries) < len(migrations) {
		return fmt.Errorf("canonical migration inventory count = %d, need at least %d", len(entries), len(migrations))
	}
	for index, migration := range migrations {
		entry := entries[index]
		if entry.IsDir() || entry.Name() != migration.CanonicalFilename {
			return fmt.Errorf("canonical migration inventory[%d] = %q, want file %q", index, entry.Name(), migration.CanonicalFilename)
		}
	}
	return nil
}

func (rooted prefixedFS) Open(name string) (fs.File, error) {
	if !fs.ValidPath(name) {
		return nil, &fs.PathError{Op: "open", Path: name, Err: fs.ErrInvalid}
	}
	return rooted.files.Open(path.Join(rooted.prefix, name))
}

func validLiquibaseChecksum(value string) bool {
	return strings.HasPrefix(value, legacyLiquibaseChecksumPrefix) &&
		validLowerHex(strings.TrimPrefix(value, legacyLiquibaseChecksumPrefix), legacyLiquibaseChecksumHexLength)
}

func validCanonicalMigrationFilename(filename string, version string) bool {
	prefix := version + "__"
	if !strings.HasPrefix(filename, prefix) || !strings.HasSuffix(filename, ".sql") {
		return false
	}
	description := strings.TrimSuffix(strings.TrimPrefix(filename, prefix), ".sql")
	if description == "" {
		return false
	}
	for _, character := range description {
		if (character < 'a' || character > 'z') &&
			(character < '0' || character > '9') &&
			character != '_' {
			return false
		}
	}
	return true
}

func validLowerHex(value string, expectedLength int) bool {
	if len(value) != expectedLength || value != strings.ToLower(value) {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func checksum(content []byte) string {
	digest := sha256.Sum256(content)
	return hex.EncodeToString(digest[:])
}

func migrationVersion(number int) string {
	return fmt.Sprintf("V%03d", number)
}
