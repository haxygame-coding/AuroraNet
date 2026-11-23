package daemonaddr

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCarriesIdentity(t *testing.T) {
	tests := []struct {
		addr string
		want bool
	}{
		{"unix:///var/run/auroranet.sock", true},
		{"unix:///var/run/auroranet/default.sock", true},
		{"npipe://auroranet", true},
		{`npipe://\\.\pipe\ProtectedPrefix\Administrators\auroranet`, true},
		{"tcp://127.0.0.1:41731", false},
		{"tcp://localhost:41731", false},
		{"", false},
		{"/var/run/auroranet.sock", false},
	}

	for _, tt := range tests {
		t.Run(tt.addr, func(t *testing.T) {
			assert.Equal(t, tt.want, CarriesIdentity(tt.addr), "address %q", tt.addr)
		})
	}
}
