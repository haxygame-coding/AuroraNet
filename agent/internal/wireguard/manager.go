package wireguard

import (
	"auroranet/agent/internal/models"
	"fmt"
	"golang.zx2c4.com/wireguard/wgctrl"
	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
	"net"
	"os/exec"
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

// EnsureInterface checks if the interface exists and creates it if it doesn't.
func (m *Manager) EnsureInterface(name string) error {
	_, err := net.InterfaceByName(name)
	if err == nil {
		// Interface already exists
		return nil
	}

	// Interface doesn't exist, try to create it
	// Using ip link add dev <name> type wireguard
	cmd := exec.Command("ip", "link", "add", "dev", name, "type", "wireguard")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to create interface %s: %v, output: %s", name, err, string(out))
	}

	// Bring the interface up
	cmd = exec.Command("ip", "link", "set", "dev", name, "up")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to bring interface %s up: %v, output: %s", name, err, string(out))
	}

	return nil
}

// SetIP assigns an IPv4 address to the interface.
func (m *Manager) SetIP(name string, ip string) error {
	// Using ip addr add <ip>/24 dev <name>
	// We use /24 as a default for the prototype, should ideally come from network config
	cmd := exec.Command("ip", "addr", "replace", fmt.Sprintf("%s/24", ip), "dev", name)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to set IP %s on %s: %v, output: %s", ip, name, err, string(out))
	}
	return nil
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

// ApplyConfig updates the WireGuard interface with the provided peers.
func (m *Manager) ApplyConfig(name string, privateKey string, listenPort int, peers []models.Peer) error {
	key, err := wgtypes.ParseKey(privateKey)
	if err != nil {
		return fmt.Errorf("failed to parse private key: %w", err)
	}

	cfg := wgtypes.Config{
		PrivateKey:   &key,
		ListenPort:   &listenPort,
		ReplacePeers: true,
	}

	for _, p := range peers {
		peerKey, err := wgtypes.ParseKey(p.PublicKey)
		if err != nil {
			continue // Skip invalid keys
		}

		var endpoint *net.UDPAddr
		if p.Endpoint != "" {
			addr, err := net.ResolveUDPAddr("udp", p.Endpoint)
			if err == nil {
				endpoint = addr
			}
		}

		_, allowedIP, err := net.ParseCIDR(fmt.Sprintf("%s/32", p.IPv4Address))
		if err != nil {
			continue
		}

		peerCfg := wgtypes.PeerConfig{
			PublicKey:         peerKey,
			Endpoint:          endpoint,
			ReplaceAllowedIPs: true,
			AllowedIPs:        []net.IPNet{*allowedIP},
		}
		cfg.Peers = append(cfg.Peers, peerCfg)
	}

	if err := m.client.ConfigureDevice(name, cfg); err != nil {
		return fmt.Errorf("failed to configure device %s: %w", name, err)
	}

	return nil
}
