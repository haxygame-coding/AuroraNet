package api

import (
	"net/http"
)

func (a *API) SetupRoutes() *http.ServeMux {
	mux := http.NewServeMux()

	// Networks
	mux.HandleFunc("GET /api/networks", a.ListNetworks)
	mux.HandleFunc("POST /api/networks", a.CreateNetwork)
	mux.HandleFunc("GET /api/networks/{id}", a.GetNetwork)
	mux.HandleFunc("DELETE /api/networks/{id}", a.DeleteNetwork)

	// Nodes
	mux.HandleFunc("GET /api/nodes", a.ListNodes)
	mux.HandleFunc("POST /api/nodes", a.CreateNode)
	mux.HandleFunc("DELETE /api/nodes/{id}", a.DeleteNode)

	// Enrollment
	mux.HandleFunc("POST /api/enroll", a.Enroll)

	return mux
}
