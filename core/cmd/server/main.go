package main

import (
	"auroranet/core/api"
	"auroranet/core/db"
	"auroranet/core/internal/repository"
	"log"
	"net/http"
	"os"
)

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
	log.Printf("Starting Core Backend server on %s...", port)
	if err := http.ListenAndServe(port, router); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
