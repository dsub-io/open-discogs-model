package model

import (
	"crypto/sha256"
	"database/sql"
	"database/sql/driver"
	"errors"
	"fmt"
)

var (
	ErrInvalidSHA256DigestLength = errors.New("SHA-256 digest must contain exactly 32 bytes")
	ErrInvalidSHA256DigestSource = errors.New("SHA-256 digest database value must be bytea")
	ErrNilSHA256DigestReceiver   = errors.New("SHA-256 digest scan receiver is nil")
)

// SHA256Digest is the fixed-width representation used by canonical SHA-256 columns.
type SHA256Digest [sha256.Size]byte

var (
	_ sql.Scanner   = (*SHA256Digest)(nil)
	_ driver.Valuer = SHA256Digest{}
)

// NewSHA256Digest validates and copies a database or hashing result.
func NewSHA256Digest(value []byte) (SHA256Digest, error) {
	if len(value) != sha256.Size {
		return SHA256Digest{}, fmt.Errorf(
			"%w: got %d bytes",
			ErrInvalidSHA256DigestLength,
			len(value),
		)
	}
	var digest SHA256Digest
	copy(digest[:], value)
	return digest, nil
}

// Bytes returns a copy suitable for a PostgreSQL bytea parameter.
func (digest SHA256Digest) Bytes() []byte {
	value := make([]byte, sha256.Size)
	copy(value, digest[:])
	return value
}

// Scan reads PostgreSQL bytea without making relation models non-comparable.
func (digest *SHA256Digest) Scan(value any) error {
	if digest == nil {
		return ErrNilSHA256DigestReceiver
	}
	encoded, ok := value.([]byte)
	if !ok {
		return fmt.Errorf("%w: got %T", ErrInvalidSHA256DigestSource, value)
	}
	parsed, err := NewSHA256Digest(encoded)
	if err != nil {
		return err
	}
	*digest = parsed
	return nil
}

// Value writes the fixed-width digest as PostgreSQL bytea.
func (digest SHA256Digest) Value() (driver.Value, error) {
	return digest.Bytes(), nil
}
