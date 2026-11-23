//go:build ios

package AuroraNetSDK

import "github.com/netbirdio/netbird/version"

// GoClientVersion returns the AuroraNet Go client version that was baked into
// the framework at compile time via
// -ldflags "-X github.com/netbirdio/netbird/version.version=<version>".
func GoClientVersion() string {
	return version.AuroraNetVersion()
}
