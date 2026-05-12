package main

import (
	"auroranet/core/api"
	"auroranet/core/db"
	"auroranet/core/internal/repository"
	"log"
	"net"
	"net/http"
	"os"
)

func getLocalIP() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return "localhost"
	}
	for _, address := range addrs {
		if ipnet, ok := address.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ipnet.IP.To4() != nil {
				return ipnet.IP.String()
			}
		}
	}
	return "localhost"
}

func main() {
	dbPath := "auroranet.db"
	
	log.Printf("Initializing database at %s...", dbPath)
	database, err := db.InitDB(dbPath)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.Close()

	log.Println("Database initialized successfully!")
	
	// Si on est en mode test/init, on peut s'arrêter là
	if os.Getenv("INIT_ONLY") == "true" {
		return
	}

	// Setup Repository and API
	repo := repository.NewSQLiteRepository(database)
	apiHandler := api.NewAPI(repo)
	router := apiHandler.SetupRoutes()

	port := ":8080"
	localIP := getLocalIP()
	log.Printf("Starting Core Backend server on %s...", port)
	log.Printf("Dashboard available at: http://%s%s", localIP, port)
	
	if err := http.ListenAndServe(port, router); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
