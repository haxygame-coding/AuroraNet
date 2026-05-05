package api

import (
	"auroranet/core/internal/models"
	"auroranet/core/internal/repository"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"github.com/google/uuid"
	"net/http"
	"os"
	"time"
)

// ... existing code ...

// Helper to generate a random secret
func generateSecret() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return uuid.New().String()
	}
	return hex.EncodeToString(b)
}

// Enrollment Handler

func (a *API) Enroll(w http.ResponseWriter, r *http.Request) {
	var req models.EnrollmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	// 1. Validate Token
	token, err := a.repo.GetEnrollmentToken(req.Token)
	if err != nil {
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	if token == nil {
		http.Error(w, "invalid or expired token", http.StatusUnauthorized)
		return
	}

	// 2. Allocate IP
	ip, err := a.repo.GetNextAvailableIP(token.NetworkID)
	if err != nil {
		http.Error(w, "failed to allocate IP", http.StatusInternalServerError)
		return
	}

	// 3. Create Node
	node := &models.Node{
		ID:          uuid.New().String(),
		NetworkID:   token.NetworkID,
		Name:        req.SystemInfo.Hostname,
		PublicKey:   req.PublicKey,
		IPv4Address: ip,
		Secret:      generateSecret(),
	}

	if err := a.repo.CreateNode(node); err != nil {
		http.Error(w, "failed to create node", http.StatusInternalServerError)
		return
	}

	// 4. Consume Token
	if err := a.repo.ConsumeToken(req.Token); err != nil {
		// Log error but continue since node is created
	}

	// 5. Respond
	resp := models.EnrollmentResponse{
		NodeID:      node.ID,
		NodeSecret:  node.Secret,
		IPv4Address: node.IPv4Address,
	}

	a.jsonResponse(w, http.StatusCreated, resp)
}


type API struct {
	repo repository.Repository
}

func NewAPI(repo repository.Repository) *API {
	return &API{repo: repo}
}

// AuthMiddleware protects routes from unauthorized access.
func (a *API) AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie("aura_session")
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		session, err := a.repo.GetSession(cookie.Value)
		if err != nil || session == nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		if time.Now().After(session.ExpiresAt) {
			a.repo.DeleteSession(cookie.Value)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func (a *API) Login(w http.ResponseWriter, r *http.Request) {
	var req models.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}

	expectedPassword := os.Getenv("DASHBOARD_PASSWORD")
	if expectedPassword == "" {
		expectedPassword = "admin" // Default for dev
	}

	if req.Password != expectedPassword {
		http.Error(w, "invalid password", http.StatusUnauthorized)
		return
	}

	token := generateSecret()
	expiresAt := time.Now().Add(24 * time.Hour)

	session := &models.Session{
		Token:     token,
		ExpiresAt: expiresAt,
	}

	if err := a.repo.CreateSession(session); err != nil {
		http.Error(w, "failed to create session", http.StatusInternalServerError)
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:     "aura_session",
		Value:    token,
		Expires:  expiresAt,
		HttpOnly: true,
		Path:     "/",
		SameSite: http.SameSiteStrictMode,
	})

	a.jsonResponse(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *API) Logout(w http.ResponseWriter, r *http.Request) {
	cookie, err := r.Cookie("aura_session")
	if err == nil {
		a.repo.DeleteSession(cookie.Value)
	}

	http.SetCookie(w, &http.Cookie{
		Name:     "aura_session",
		Value:    "",
		Expires:  time.Now().Add(-1 * time.Hour),
		HttpOnly: true,
		Path:     "/",
	})

	a.jsonResponse(w, http.StatusOK, map[string]string{"status": "ok"})
}

// Helper for JSON responses
func (a *API) jsonResponse(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if data != nil {
		json.NewEncoder(w).Encode(data)
	}
}

// Networks Handlers

func (a *API) ListNetworks(w http.ResponseWriter, r *http.Request) {
	networks, err := a.repo.ListNetworks()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	a.jsonResponse(w, http.StatusOK, networks)
}

func (a *API) CreateNetwork(w http.ResponseWriter, r *http.Request) {
	var n models.Network
	if err := json.NewDecoder(r.Body).Decode(&n); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if n.ID == "" {
		n.ID = uuid.New().String()
	}

	if err := a.repo.CreateNetwork(&n); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	a.jsonResponse(w, http.StatusCreated, n)
}

func (a *API) GetNetwork(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	network, err := a.repo.GetNetwork(id)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if network == nil {
		http.Error(w, "network not found", http.StatusNotFound)
		return
	}
	a.jsonResponse(w, http.StatusOK, network)
}

func (a *API) DeleteNetwork(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := a.repo.DeleteNetwork(id); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	a.jsonResponse(w, http.StatusNoContent, nil)
}

// Nodes Handlers

func (a *API) ListNodes(w http.ResponseWriter, r *http.Request) {
	networkID := r.URL.Query().Get("network_id")
	nodes, err := a.repo.ListNodes(networkID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	a.jsonResponse(w, http.StatusOK, nodes)
}

func (a *API) CreateNode(w http.ResponseWriter, r *http.Request) {
	var n models.Node
	if err := json.NewDecoder(r.Body).Decode(&n); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if n.ID == "" {
		n.ID = uuid.New().String()
	}

	if err := a.repo.CreateNode(&n); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	a.jsonResponse(w, http.StatusCreated, n)
}

func (a *API) DeleteNode(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := a.repo.DeleteNode(id); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	a.jsonResponse(w, http.StatusNoContent, nil)
}
