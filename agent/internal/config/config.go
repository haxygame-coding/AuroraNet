package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type Config struct {
	BackendURL      string `json:"backend_url"`
	EnrollmentToken string `json:"enrollment_token,omitempty"`
	NodeID          string `json:"node_id,omitempty"`
	NodeSecret      string `json:"node_secret,omitempty"`
	PrivateKey      string `json:"private_key,omitempty"`
	PublicKey       string `json:"public_key,omitempty"`
	IPv4Address     string `json:"ipv4_address,omitempty"`
	InterfaceName   string `json:"interface_name"`
	ListenPort      int    `json:"listen_port,omitempty"`

	filePath string
}

func NewConfig(path string) *Config {
	return &Config{
		InterfaceName: "aura0",
		ListenPort:    51820,
		filePath:      path,
	}
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return NewConfig(path), nil
		}
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	cfg := NewConfig(path)
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	return cfg, nil
}

func (c *Config) Save() error {
	if c.filePath == "" {
		return fmt.Errorf("no config file path specified")
	}

	// Ensure directory exists
	dir := filepath.Dir(c.filePath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	if err := os.WriteFile(c.filePath, data, 0600); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	return nil
}
