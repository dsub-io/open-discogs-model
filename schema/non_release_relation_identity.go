package schema

import (
	"bytes"
	_ "embed"
)

//go:embed contracts/non-release-relation-identity-v1.tsv
var nonReleaseRelationIdentityVectors []byte

// NonReleaseRelationIdentityVectors returns a copy of the cross-language golden vectors.
func NonReleaseRelationIdentityVectors() []byte {
	return bytes.Clone(nonReleaseRelationIdentityVectors)
}
