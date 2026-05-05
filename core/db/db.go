package db

import (
	"database/sql"
	_ "embed"
	"fmt"
	_ "github.com/mattn/go-sqlite3"
)

//go:embed schema.sql
var schemaSQL string

// InitDB initializes the SQLite database at the given path and runs the schema.
func InitDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// Enable foreign keys
	if _, err := db.Exec("PRAGMA foreign_keys = ON;"); err != nil {
		return nil, fmt.Errorf("failed to enable foreign keys: %w", err)
	}

	// Run schema
	if _, err := db.Exec(schemaSQL); err != nil {
		return nil, fmt.Errorf("failed to execute schema: %w", err)
	}

	return db, nil
}
