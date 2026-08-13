package schema

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/csv"
	"encoding/hex"
	"strconv"
	"testing"
	"unicode/utf16"
)

const (
	nonReleaseIdentityVectorColumnCount = 10
	nonReleaseIdentityPrefix            = "open-discogs/non-release-relation-identity/v1"
	nonReleaseIdentitySlotPrefix        = "open-discogs/non-release-relation-slot/v1"
)

var nonReleaseIdentityFieldCounts = map[string]int{
	"artist_name_variation": 1,
	"artist_url":            1,
	"label_url":             1,
	"master_video":          3,
}

type nonReleaseRelationIdentityVector struct {
	kind           string
	id             string
	relation       string
	fields         [3]string
	identitySHA256 string
	attempt        string
	slot           string
	legacyJavaHash string
}

func TestNonReleaseRelationIdentityGoldenVectors(t *testing.T) {
	t.Parallel()

	vectors := readNonReleaseRelationIdentityVectors(t)
	digestRelations := make(map[string]struct{}, len(nonReleaseIdentityFieldCounts))
	collidedIdentities := make(map[int32]map[string]struct{})
	for _, vector := range vectors {
		switch vector.kind {
		case "digest":
			digestRelations[vector.relation] = struct{}{}
			assertNonReleaseIdentityDigestVector(t, vector)
			if vector.legacyJavaHash != identityVectorUnused {
				hash, err := strconv.ParseInt(vector.legacyJavaHash, 10, 32)
				if err != nil {
					t.Fatalf("vector %s legacy Java hash is invalid: %v", vector.id, err)
				}
				value := decodeIdentityVectorValue(t, vector.id, vector.fields[0])
				if actual := javaStringHash(value); actual != int32(hash) {
					t.Fatalf("vector %s Java hash = %d, want %d", vector.id, actual, hash)
				}
				if collidedIdentities[int32(hash)] == nil {
					collidedIdentities[int32(hash)] = make(map[string]struct{})
				}
				collidedIdentities[int32(hash)][vector.identitySHA256] = struct{}{}
			}
		case "slot":
			assertNonReleaseIdentitySlotVector(t, vector)
		default:
			t.Fatalf("vector %s has unknown kind %q", vector.id, vector.kind)
		}
	}
	if len(digestRelations) != len(nonReleaseIdentityFieldCounts) {
		t.Fatalf("digest relation coverage = %v, want %v", digestRelations, nonReleaseIdentityFieldCounts)
	}
	if len(collidedIdentities[2112]) != 2 {
		t.Fatalf("Java hash 2112 has %d canonical identities, want 2", len(collidedIdentities[2112]))
	}
}

func TestNonReleaseRelationIdentityVectorsReturnsCopy(t *testing.T) {
	t.Parallel()

	first := NonReleaseRelationIdentityVectors()
	second := NonReleaseRelationIdentityVectors()
	if len(first) == 0 || !bytes.Equal(first, second) {
		t.Fatal("NonReleaseRelationIdentityVectors() returned invalid content")
	}
	first[0] ^= 0xff
	if bytes.Equal(first, NonReleaseRelationIdentityVectors()) {
		t.Fatal("NonReleaseRelationIdentityVectors() returned shared mutable storage")
	}
}

func readNonReleaseRelationIdentityVectors(t *testing.T) []nonReleaseRelationIdentityVector {
	t.Helper()
	reader := csv.NewReader(bytes.NewReader(NonReleaseRelationIdentityVectors()))
	reader.Comma = '\t'
	reader.FieldsPerRecord = nonReleaseIdentityVectorColumnCount
	records, err := reader.ReadAll()
	if err != nil {
		t.Fatalf("read golden vectors: %v", err)
	}
	wantHeader := []string{
		"kind", "id", "relation", "field_1", "field_2", "field_3",
		"identity_sha256", "attempt", "slot", "legacy_java_hash",
	}
	if len(records) < 2 || !equalStrings(records[0], wantHeader) {
		t.Fatalf("golden vector header = %v, want %v", records[0], wantHeader)
	}
	vectors := make([]nonReleaseRelationIdentityVector, 0, len(records)-1)
	for _, record := range records[1:] {
		vectors = append(vectors, nonReleaseRelationIdentityVector{
			kind:           record[0],
			id:             record[1],
			relation:       record[2],
			fields:         [3]string{record[3], record[4], record[5]},
			identitySHA256: record[6],
			attempt:        record[7],
			slot:           record[8],
			legacyJavaHash: record[9],
		})
	}
	return vectors
}

func assertNonReleaseIdentityDigestVector(t *testing.T, vector nonReleaseRelationIdentityVector) {
	t.Helper()
	fieldCount, exists := nonReleaseIdentityFieldCounts[vector.relation]
	if !exists {
		t.Fatalf("vector %s has unknown relation %q", vector.id, vector.relation)
	}
	preimage := bytes.NewBuffer(nil)
	preimage.WriteString(nonReleaseIdentityPrefix)
	preimage.WriteByte(0)
	preimage.WriteString(vector.relation)
	preimage.WriteByte(0)
	for index, encoded := range vector.fields {
		if index >= fieldCount {
			if encoded != identityVectorUnused {
				t.Fatalf("vector %s field %d must be unused", vector.id, index+1)
			}
			continue
		}
		value := trimIdentityValue(decodeIdentityVectorValue(t, vector.id, encoded))
		if value == nil {
			preimage.WriteByte(0)
			continue
		}
		preimage.WriteByte(1)
		length := make([]byte, 4)
		binary.BigEndian.PutUint32(length, uint32(len(value)))
		preimage.Write(length)
		preimage.Write(value)
	}
	actual := sha256.Sum256(preimage.Bytes())
	if hex.EncodeToString(actual[:]) != vector.identitySHA256 {
		t.Fatalf("vector %s digest = %x, want %s", vector.id, actual, vector.identitySHA256)
	}
}

func assertNonReleaseIdentitySlotVector(t *testing.T, vector nonReleaseRelationIdentityVector) {
	t.Helper()
	digest, err := hex.DecodeString(vector.identitySHA256)
	if err != nil || len(digest) != sha256.Size {
		t.Fatalf("vector %s identity digest is invalid: %v", vector.id, err)
	}
	attempt, err := strconv.ParseUint(vector.attempt, 10, 32)
	if err != nil {
		t.Fatalf("vector %s attempt is invalid: %v", vector.id, err)
	}
	expected, err := strconv.ParseInt(vector.slot, 10, 32)
	if err != nil {
		t.Fatalf("vector %s slot is invalid: %v", vector.id, err)
	}
	preimage := bytes.NewBuffer(nil)
	preimage.WriteString(nonReleaseIdentitySlotPrefix)
	preimage.WriteByte(0)
	preimage.WriteString(vector.relation)
	preimage.WriteByte(0)
	preimage.Write(digest)
	attemptBytes := make([]byte, 4)
	binary.BigEndian.PutUint32(attemptBytes, uint32(attempt))
	preimage.Write(attemptBytes)
	actualDigest := sha256.Sum256(preimage.Bytes())
	actual := int32(binary.BigEndian.Uint32(actualDigest[:4]))
	if actual != int32(expected) {
		t.Fatalf("vector %s slot = %d, want %d", vector.id, actual, expected)
	}
}

func javaStringHash(value []byte) int32 {
	var hash int32
	for _, codeUnit := range utf16.Encode([]rune(string(value))) {
		hash = 31*hash + int32(codeUnit)
	}
	return hash
}
