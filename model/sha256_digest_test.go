package model

import (
	"bytes"
	"errors"
	"testing"
)

func TestSHA256DigestDatabaseBoundary(t *testing.T) {
	t.Parallel()

	source := make([]byte, 32)
	for index := range source {
		source[index] = byte(index)
	}
	digest, err := NewSHA256Digest(source)
	if err != nil {
		t.Fatalf("NewSHA256Digest() error = %v", err)
	}
	source[0] = 255
	if digest[0] != 0 {
		t.Fatal("NewSHA256Digest() retained caller-owned storage")
	}

	encoded := digest.Bytes()
	encoded[1] = 255
	if digest[1] != 1 {
		t.Fatal("Bytes() exposed digest storage")
	}

	databaseValue, err := digest.Value()
	if err != nil {
		t.Fatalf("Value() error = %v", err)
	}
	valueBytes, ok := databaseValue.([]byte)
	if !ok || !bytes.Equal(valueBytes, digest[:]) {
		t.Fatalf("Value() = %T %v", databaseValue, databaseValue)
	}

	var scanned SHA256Digest
	if err := scanned.Scan(valueBytes); err != nil {
		t.Fatalf("Scan() error = %v", err)
	}
	if scanned != digest {
		t.Fatalf("Scan() = %v, want %v", scanned, digest)
	}
}

func TestSHA256DigestRejectsInvalidValues(t *testing.T) {
	t.Parallel()

	if _, err := NewSHA256Digest(make([]byte, 31)); !errors.Is(err, ErrInvalidSHA256DigestLength) {
		t.Fatalf("NewSHA256Digest(short) error = %v", err)
	}
	var digest SHA256Digest
	if err := digest.Scan("not bytea"); !errors.Is(err, ErrInvalidSHA256DigestSource) {
		t.Fatalf("Scan(string) error = %v", err)
	}
	if err := digest.Scan(make([]byte, 33)); !errors.Is(err, ErrInvalidSHA256DigestLength) {
		t.Fatalf("Scan(long) error = %v", err)
	}
	var nilDigest *SHA256Digest
	if err := nilDigest.Scan(make([]byte, 32)); !errors.Is(err, ErrNilSHA256DigestReceiver) {
		t.Fatalf("Scan(nil receiver) error = %v", err)
	}
}

func TestReleaseRelationModelsRemainComparable(t *testing.T) {
	t.Parallel()

	requireComparable(ReleaseItemCreditedArtist{})
	requireComparable(ReleaseItemFormat{})
	requireComparable(ReleaseItemIdentifier{})
	requireComparable(ReleaseItemImage{})
	requireComparable(ReleaseItemTrack{})
	requireComparable(ReleaseItemVideo{})
	requireComparable(ReleaseItemWork{})
}

func requireComparable[T comparable](T) {}
