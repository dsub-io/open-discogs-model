package schema

import (
	"bytes"
	_ "embed"
)

//go:embed contracts/release-relation-identity-v1.tsv
var releaseRelationIdentityVectors []byte

// ReleaseRelationIdentityVectors returns a copy of the cross-language golden vectors.
func ReleaseRelationIdentityVectors() []byte {
	return bytes.Clone(releaseRelationIdentityVectors)
}
