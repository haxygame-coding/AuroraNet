package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"runtime"
	"time"
)

type EnrollmentRequest struct {
	Token      string     `json:"token"`
	PublicKey  string     `json:"public_key"`
	SystemInfo SystemInfo `json:"system_info"`
}

type SystemInfo struct {
	Hostname string `json:"hostname"`
	OS       string `json:"os"`
	Arch     string `json:"arch"`
	Version  string `json:"version"`
}

type EnrollmentResponse struct {
	NodeID      string `json:"node_id"`
	NodeSecret  string `json:"node_secret"`
	IPv4Address string `json:"ipv4_address"`
}

type Client struct {
	baseURL    string
	httpClient *http.Client
}

func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (c *Client) Enroll(token, publicKey, hostname string) (*EnrollmentResponse, error) {
	reqBody := EnrollmentRequest{
		Token:     token,
		PublicKey: publicKey,
		SystemInfo: SystemInfo{
			Hostname: hostname,
			OS:       runtime.GOOS,
			Arch:     runtime.GOARCH,
			Version:  "0.1.0", // Placeholder version
		},
	}

	data, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal enrollment request: %w", err)
	}

	url := fmt.Sprintf("%s/api/enroll", c.baseURL)
	resp, err := c.httpClient.Post(url, "application/json", bytes.NewBuffer(data))
	if err != nil {
		return nil, fmt.Errorf("failed to send enrollment request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return nil, fmt.Errorf("enrollment failed with status: %s", resp.Status)
	}

	var result EnrollmentResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode enrollment response: %w", err)
	}

	return &result, nil
}
