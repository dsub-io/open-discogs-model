package schema

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/csv"
	"encoding/hex"
	"strconv"
	"strings"
	"testing"
	"unicode/utf8"
)

const (
	identityVectorColumnCount = 11
	identityVectorNull        = "null"
	identityVectorUnused      = "-"
	identityVectorHexPrefix   = "hex:"
	identityPrefix            = "open-discogs/release-relation-identity/v1"
	identitySlotPrefix        = "open-discogs/release-relation-slot/v1"
)

var identityFieldCounts = map[string]int{
	"credited_artist": 1,
	"format":          4,
	"identifier":      3,
	"image":           1,
	"track":           3,
	"video":           3,
	"work":            1,
}

type releaseRelationIdentityVector struct {
	kind           string
	id             string
	relation       string
	fields         [4]string
	identitySHA256 string
	attempt        string
	slot           string
	expected       string
}

func TestReleaseRelationIdentityGoldenVectors(t *testing.T) {
	t.Parallel()

	vectors := readReleaseRelationIdentityVectors(t)
	digestRelations := make(map[string]struct{}, len(identityFieldCounts))
	for _, vector := range vectors {
		switch vector.kind {
		case "digest":
			digestRelations[vector.relation] = struct{}{}
			assertIdentityDigestVector(t, vector)
		case "slot":
			assertIdentitySlotVector(t, vector)
		case "description":
			assertDescriptionVector(t, vector)
		default:
			t.Fatalf("vector %s has unknown kind %q", vector.id, vector.kind)
		}
	}
	if len(digestRelations) != len(identityFieldCounts) {
		t.Fatalf("digest relation coverage = %v, want %v", digestRelations, identityFieldCounts)
	}
}

func TestReleaseRelationIdentityVectorsReturnsCopy(t *testing.T) {
	t.Parallel()

	first := ReleaseRelationIdentityVectors()
	second := ReleaseRelationIdentityVectors()
	if len(first) == 0 || !bytes.Equal(first, second) {
		t.Fatal("ReleaseRelationIdentityVectors() returned invalid content")
	}
	first[0] ^= 0xff
	if bytes.Equal(first, ReleaseRelationIdentityVectors()) {
		t.Fatal("ReleaseRelationIdentityVectors() returned shared mutable storage")
	}
}

func readReleaseRelationIdentityVectors(t *testing.T) []releaseRelationIdentityVector {
	t.Helper()
	reader := csv.NewReader(bytes.NewReader(ReleaseRelationIdentityVectors()))
	reader.Comma = '\t'
	reader.FieldsPerRecord = identityVectorColumnCount
	records, err := reader.ReadAll()
	if err != nil {
		t.Fatalf("read golden vectors: %v", err)
	}
	if len(records) < 2 {
		t.Fatal("golden vector resource is empty")
	}
	wantHeader := []string{
		"kind", "id", "relation", "field_1", "field_2", "field_3", "field_4",
		"identity_sha256", "attempt", "slot", "expected",
	}
	if !equalStrings(records[0], wantHeader) {
		t.Fatalf("golden vector header = %v, want %v", records[0], wantHeader)
	}
	vectors := make([]releaseRelationIdentityVector, 0, len(records)-1)
	for _, record := range records[1:] {
		vectors = append(vectors, releaseRelationIdentityVector{
			kind:           record[0],
			id:             record[1],
			relation:       record[2],
			fields:         [4]string{record[3], record[4], record[5], record[6]},
			identitySHA256: record[7],
			attempt:        record[8],
			slot:           record[9],
			expected:       record[10],
		})
	}
	return vectors
}

func assertIdentityDigestVector(t *testing.T, vector releaseRelationIdentityVector) {
	t.Helper()
	fieldCount, exists := identityFieldCounts[vector.relation]
	if !exists {
		t.Fatalf("vector %s has unknown relation %q", vector.id, vector.relation)
	}
	preimage := bytes.NewBuffer(nil)
	preimage.WriteString(identityPrefix)
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
		value := decodeIdentityVectorValue(t, vector.id, encoded)
		value = trimIdentityValue(value)
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
		t.Fatalf(
			"vector %s digest = %x, want %s",
			vector.id,
			actual,
			vector.identitySHA256,
		)
	}
}

func assertIdentitySlotVector(t *testing.T, vector releaseRelationIdentityVector) {
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
	preimage.WriteString(identitySlotPrefix)
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

func assertDescriptionVector(t *testing.T, vector releaseRelationIdentityVector) {
	t.Helper()
	parts := make([]string, 0, len(vector.fields))
	for _, encoded := range vector.fields {
		value := trimIdentityValue(decodeIdentityVectorValue(t, vector.id, encoded))
		if value != nil {
			parts = append(parts, "[d:"+string(value)+"]")
		}
	}
	var actual []byte
	if len(parts) > 0 {
		actual = []byte(strings.Join(parts, ","))
	}
	expected := decodeIdentityVectorValue(t, vector.id, vector.expected)
	if !bytes.Equal(actual, expected) {
		t.Fatalf("vector %s reduced description = %q, want %q", vector.id, actual, expected)
	}
}

func decodeIdentityVectorValue(t *testing.T, id, encoded string) []byte {
	t.Helper()
	if encoded == identityVectorNull {
		return nil
	}
	if !strings.HasPrefix(encoded, identityVectorHexPrefix) {
		t.Fatalf("vector %s value %q is not null or hex", id, encoded)
	}
	value, err := hex.DecodeString(strings.TrimPrefix(encoded, identityVectorHexPrefix))
	if err != nil || !utf8.Valid(value) {
		t.Fatalf("vector %s value %q is not UTF-8 hex: %v", id, encoded, err)
	}
	return value
}

func trimIdentityValue(value []byte) []byte {
	if value == nil {
		return nil
	}
	trimmed := strings.TrimFunc(string(value), isIdentityWhitespace)
	if trimmed == "" {
		return nil
	}
	return []byte(trimmed)
}

func isIdentityWhitespace(value rune) bool {
	return value >= '\u0009' && value <= '\u000d' ||
		value == '\u0020' || value == '\u0085' || value == '\u00a0' ||
		value == '\u1680' || value >= '\u2000' && value <= '\u200a' ||
		value == '\u2028' || value == '\u2029' || value == '\u202f' ||
		value == '\u205f' || value == '\u3000'
}

func equalStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}
