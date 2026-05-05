package models

import "time"

// Network represents a private mesh network.
type Network struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	IPv4Range string    `json:"ipv4_range"`
	CreatedAt time.Time `json:"created_at"`
}

// Node represents a device in a network.
type Node struct {
	ID          string    `json:"id"`
	NetworkID   string    `json:"network_id"`
	Name        string    `json:"name"`
	PublicKey   string    `json:"public_key"`
	IPv4Address string    `json:"ipv4_address"`
	Secret      string    `json:"secret"`
	CreatedAt   time.Time `json:"created_at"`
}

// EnrollmentToken represents a one-time token for node registration.
type EnrollmentToken struct {
	Token     string    `json:"token"`
	NetworkID string    `json:"network_id"`
	Used      bool      `json:"used"`
	CreatedAt time.Time `json:"created_at"`
}

// EnrollmentRequest is the data sent by the agent to enroll.
type EnrollmentRequest struct {
	Token      string     `json:"token"`
	PublicKey  string     `json:"public_key"`
	SystemInfo SystemInfo `json:"system_info"`
}

// SystemInfo contains basic information about the agent's host.
type SystemInfo struct {
	Hostname string `json:"hostname"`
	OS       string `json:"os"`
	Arch     string `json:"arch"`
	Version  string `json:"version"`
}

// EnrollmentResponse is the data sent back to the agent after successful enrollment.
type EnrollmentResponse struct {
	NodeID      string `json:"node_id"`
	NodeSecret  string `json:"node_secret"`
	IPv4Address string `json:"ipv4_address"`
}

// LoginRequest is used for dashboard authentication.
type LoginRequest struct {
	Password string `json:"password"`
}

// Session represents a dashboard user session.
type Session struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}

