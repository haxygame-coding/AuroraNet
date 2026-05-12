package api

import (
	"auroranet/agent/internal/models"
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
)

type Client struct {
	baseURL string
}

func NewClient(baseURL string) *Client {
	return &Client{baseURL: baseURL}
}

func (c *Client) Enroll(token, publicKey, hostname string) (*models.EnrollmentResponse, error) {
	req := models.EnrollmentRequest{
		Token:     token,
		PublicKey: publicKey,
		SystemInfo: models.SystemInfo{
			Hostname: hostname,
		},
	}

	body, _ := json.Marshal(req)
	resp, err := http.Post(fmt.Sprintf("%s/api/enroll", c.baseURL), "application/json", bytes.NewBuffer(body))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		return nil, fmt.Errorf("enrollment failed with status: %d", resp.StatusCode)
	}

	var enrollResp models.EnrollmentResponse
	if err := json.NewDecoder(resp.Body).Decode(&enrollResp); err != nil {
		return nil, err
	}

	return &enrollResp, nil
}

func (c *Client) GetConfig(nodeID, nodeSecret string) (*models.NodeConfigResponse, error) {
	req, err := http.NewRequest("GET", fmt.Sprintf("%s/api/nodes/config", c.baseURL), nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("X-Node-ID", nodeID)
	req.Header.Set("X-Node-Secret", nodeSecret)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("config fetch failed with status: %d", resp.StatusCode)
	}

	var configResp models.NodeConfigResponse
	if err := json.NewDecoder(resp.Body).Decode(&configResp); err != nil {
		return nil, err
	}

	return &configResp, nil
}
