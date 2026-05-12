package api

import (
	"net/http"
)

func (a *API) SetupRoutes() *http.ServeMux {
	mux := http.NewServeMux()

	// Auth (Public)
	mux.HandleFunc("POST /api/login", a.Login)
	mux.HandleFunc("POST /api/logout", a.Logout)

	// Protected Routes
	protected := http.NewServeMux()

	// Networks
	protected.HandleFunc("GET /api/networks", a.ListNetworks)
	protected.HandleFunc("POST /api/networks", a.CreateNetwork)
	protected.HandleFunc("GET /api/networks/{id}", a.GetNetwork)
	protected.HandleFunc("DELETE /api/networks/{id}", a.DeleteNetwork)

	// Nodes
	protected.HandleFunc("GET /api/nodes", a.ListNodes)
	protected.HandleFunc("POST /api/nodes", a.CreateNode)
	protected.HandleFunc("DELETE /api/nodes/{id}", a.DeleteNode)

	// Enrollment Tokens
	protected.HandleFunc("GET /api/tokens", a.ListEnrollmentTokens)
	protected.HandleFunc("POST /api/tokens", a.CreateEnrollmentToken)
	protected.HandleFunc("DELETE /api/tokens/{token}", a.DeleteEnrollmentToken)

	// Apply AuthMiddleware to protected mux
	mux.Handle("/api/", a.AuthMiddleware(protected))

	// Enrollment (Public)
	mux.HandleFunc("POST /api/enroll", a.Enroll)

	// Agent Endpoints
	mux.Handle("GET /api/nodes/config", a.NodeAuthMiddleware(http.HandlerFunc(a.GetNodeConfig)))

	return mux
}
