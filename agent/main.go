package main

import (
	"auroranet/agent/internal/api"
	"auroranet/agent/internal/config"
	"auroranet/agent/internal/state"
	"auroranet/agent/internal/wireguard"
	"flag"
	"log"
	"os"
	"time"
)

func main() {
	configPath := flag.String("config", "agent_config.json", "Path to the agent configuration file")
	backendURL := flag.String("backend", "http://localhost:8080", "Backend URL")
	token := flag.String("token", "", "Enrollment token")
	flag.Parse()

	log.Println("Starting Auroranet Agent...")

	// 1. Load Config
	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	if cfg.BackendURL == "" {
		cfg.BackendURL = *backendURL
	}
	if cfg.EnrollmentToken == "" && *token != "" {
		cfg.EnrollmentToken = *token
	}

	// 2. Initialize State Machine
	initialState := state.Unenrolled
	if cfg.NodeID != "" {
		initialState = state.Active
	}
	sm := state.NewMachine(initialState)

	// 3. Initialize WireGuard Manager
	wg, err := wireguard.NewManager()
	if err != nil {
		log.Printf("Warning: WireGuard manager not available (might need root): %v", err)
	} else {
		defer wg.Close()
	}

	// 4. API Client
	apiClient := api.NewClient(cfg.BackendURL)

	// 5. Main Loop
	for {
		currentState := sm.Get()

		switch currentState {
		case state.Unenrolled:
			if cfg.EnrollmentToken == "" {
				log.Println("Error: No enrollment token provided. Please provide one via -token flag or config.")
				sm.Set(state.Error)
				break
			}

			sm.Set(state.Enrolling)
			log.Println("Starting enrollment process...")

			// Generate keys if they don't exist
			if cfg.PrivateKey == "" {
				if wg == nil {
					log.Println("Error: Cannot generate keys without WireGuard manager (root access usually required).")
					sm.Set(state.Error)
					break
				}
				priv, pub, err := wg.GenerateKeys()
				if err != nil {
					log.Fatalf("Failed to generate keys: %v", err)
				}
				cfg.PrivateKey = priv
				cfg.PublicKey = pub
				log.Println("New WireGuard keys generated.")
			}

			hostname, _ := os.Hostname()
			resp, err := apiClient.Enroll(cfg.EnrollmentToken, cfg.PublicKey, hostname)
			if err != nil {
				log.Printf("Enrollment failed: %v. Retrying in 10s...", err)
				time.Sleep(10 * time.Second)
				sm.Set(state.Unenrolled)
				break
			}

			// Success! Update config
			cfg.NodeID = resp.NodeID
			cfg.NodeSecret = resp.NodeSecret
			cfg.IPv4Address = resp.IPv4Address
			cfg.EnrollmentToken = "" // One-time use

			if err := cfg.Save(); err != nil {
				log.Printf("Failed to save config: %v", err)
			}

			log.Printf("Enrollment successful! Assigned IP: %s", cfg.IPv4Address)
			sm.Set(state.Active)

		case state.Active:
			// log.Println("Agent is active.")
			// TODO: Implement actual WireGuard configuration and polling for peers
			time.Sleep(30 * time.Second)

		case state.Error:
			log.Println("Agent is in error state. Waiting for manual intervention or restart.")
			time.Sleep(60 * time.Second)

		case state.Reconnecting:
			log.Println("Attempting to reconnect...")
			// TODO: Implement heartbeat/reconnection logic
			sm.Set(state.Active)
		}

		time.Sleep(1 * time.Second)
	}
}
