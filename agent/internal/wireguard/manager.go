package wireguard

import (
	"fmt"
	"golang.zx2c4.com/wireguard/wgctrl"
	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
)

type Manager struct {
	client *wgctrl.Client
}

func NewManager() (*Manager, error) {
	client, err := wgctrl.New()
	if err != nil {
		return nil, fmt.Errorf("failed to open wgctrl: %w", err)
	}
	return &Manager{client: client}, nil
}

func (m *Manager) Close() error {
	return m.client.Close()
}

// GenerateKeys creates a new private/public key pair.
func (m *Manager) GenerateKeys() (string, string, error) {
	priv, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		return "", "", fmt.Errorf("failed to generate private key: %w", err)
	}
	return priv.String(), priv.PublicKey().String(), nil
}

// ConfigureInterface sets the private key and listening port for the interface.
func (m *Manager) ConfigureInterface(name string, privateKey string, port int) error {
	key, err := wgtypes.ParseKey(privateKey)
	if err != nil {
		return fmt.Errorf("failed to parse private key: %w", err)
	}

	cfg := wgtypes.Config{
		PrivateKey:   &key,
		ListenPort:   &port,
		ReplacePeers: false,
	}

	if err := m.client.ConfigureDevice(name, cfg); err != nil {
		return fmt.Errorf("failed to configure device %s: %w", name, err)
	}

	return nil
}

// GetDeviceInfo returns information about the WireGuard device.
func (m *Manager) GetDeviceInfo(name string) (*wgtypes.Device, error) {
	return m.client.Device(name)
}
