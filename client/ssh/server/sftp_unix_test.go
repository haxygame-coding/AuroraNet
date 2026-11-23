//go:build !windows

package server

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestShellQuote(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{"plain path", "/usr/bin/auroranet", "'/usr/bin/auroranet'"},
		{"path with space", "/opt/net bird/auroranet", "'/opt/net bird/auroranet'"},
		{"embedded single quote", "/home/o'brien", `'/home/o'\''brien'`},
		{"multiple embedded quotes", "it's a 'test'", `'it'\''s a '\''test'\'''`},
		{"empty string", "", "''"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := shellQuote(tt.input)
			assert.Equal(t, tt.want, got, "shellQuote(%q)", tt.input)
		})
	}
}
