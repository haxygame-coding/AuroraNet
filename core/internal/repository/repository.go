package repository

import (
	"auroranet/core/internal/models"
	"database/sql"
)

type Repository interface {
	// Networks
	CreateNetwork(n *models.Network) error
	GetNetwork(id string) (*models.Network, error)
	ListNetworks() ([]models.Network, error)
	DeleteNetwork(id string) error

	// Nodes
	CreateNode(n *models.Node) error
	GetNode(id string) (*models.Node, error)
	GetNodeWithSecret(id, secret string) (*models.Node, error)
	UpdateNodeEndpoint(id, endpoint string) error
	ListNodes(networkID string) ([]models.Node, error)
	ListPeers(networkID, excludeNodeID string) ([]models.Peer, error)
	DeleteNode(id string) error

	// Enrollment
	GetEnrollmentToken(token string) (*models.EnrollmentToken, error)
	ConsumeToken(token string) error
	CreateEnrollmentToken(t *models.EnrollmentToken) error
	ListEnrollmentTokens() ([]models.EnrollmentToken, error)
	DeleteEnrollmentToken(token string) error
	GetNextAvailableIP(networkID string) (string, error)

	// Sessions
	CreateSession(s *models.Session) error
	GetSession(token string) (*models.Session, error)
	DeleteSession(token string) error
}

type SQLiteRepository struct {
	db *sql.DB
}

func NewSQLiteRepository(db *sql.DB) *SQLiteRepository {
	return &SQLiteRepository{db: db}
}

// Networks implementation

func (r *SQLiteRepository) CreateNetwork(n *models.Network) error {
	query := `INSERT INTO networks (id, name, ipv4_range) VALUES (?, ?, ?)`
	_, err := r.db.Exec(query, n.ID, n.Name, n.IPv4Range)
	return err
}

func (r *SQLiteRepository) GetNetwork(id string) (*models.Network, error) {
	n := &models.Network{}
	query := `SELECT id, name, ipv4_range, created_at FROM networks WHERE id = ?`
	err := r.db.QueryRow(query, id).Scan(&n.ID, &n.Name, &n.IPv4Range, &n.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return n, err
}

func (r *SQLiteRepository) ListNetworks() ([]models.Network, error) {
	query := `SELECT id, name, ipv4_range, created_at FROM networks`
	rows, err := r.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var networks []models.Network
	for rows.Next() {
		var n models.Network
		if err := rows.Scan(&n.ID, &n.Name, &n.IPv4Range, &n.CreatedAt); err != nil {
			return nil, err
		}
		networks = append(networks, n)
	}
	return networks, nil
}

func (r *SQLiteRepository) DeleteNetwork(id string) error {
	_, err := r.db.Exec(`DELETE FROM networks WHERE id = ?`, id)
	return err
}

// Nodes implementation

func (r *SQLiteRepository) CreateNode(n *models.Node) error {
	query := `INSERT INTO nodes (id, network_id, name, public_key, ipv4_address, secret) VALUES (?, ?, ?, ?, ?, ?)`
	_, err := r.db.Exec(query, n.ID, n.NetworkID, n.Name, n.PublicKey, n.IPv4Address, n.Secret)
	return err
}

func (r *SQLiteRepository) GetNode(id string) (*models.Node, error) {
	n := &models.Node{}
	query := `SELECT id, network_id, name, public_key, ipv4_address, secret, endpoint, last_seen_at, created_at FROM nodes WHERE id = ?`
	var lastSeen sql.NullTime
	err := r.db.QueryRow(query, id).Scan(&n.ID, &n.NetworkID, &n.Name, &n.PublicKey, &n.IPv4Address, &n.Secret, &n.Endpoint, &lastSeen, &n.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if lastSeen.Valid {
		n.LastSeenAt = lastSeen.Time
	}
	return n, err
}

func (r *SQLiteRepository) ListNodes(networkID string) ([]models.Node, error) {
	var query string
	var args []interface{}
	if networkID != "" {
		query = `SELECT id, network_id, name, public_key, ipv4_address, secret, endpoint, last_seen_at, created_at FROM nodes WHERE network_id = ?`
		args = append(args, networkID)
	} else {
		query = `SELECT id, network_id, name, public_key, ipv4_address, secret, endpoint, last_seen_at, created_at FROM nodes`
	}

	rows, err := r.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var nodes []models.Node
	for rows.Next() {
		var n models.Node
		var lastSeen sql.NullTime
		if err := rows.Scan(&n.ID, &n.NetworkID, &n.Name, &n.PublicKey, &n.IPv4Address, &n.Secret, &n.Endpoint, &lastSeen, &n.CreatedAt); err != nil {
			return nil, err
		}
		if lastSeen.Valid {
			n.LastSeenAt = lastSeen.Time
		}
		nodes = append(nodes, n)
	}
	return nodes, nil
}

func (r *SQLiteRepository) GetNodeWithSecret(id, secret string) (*models.Node, error) {
	n := &models.Node{}
	query := `SELECT id, network_id, name, public_key, ipv4_address, secret, endpoint, last_seen_at, created_at FROM nodes WHERE id = ? AND secret = ?`
	var lastSeen sql.NullTime
	err := r.db.QueryRow(query, id, secret).Scan(&n.ID, &n.NetworkID, &n.Name, &n.PublicKey, &n.IPv4Address, &n.Secret, &n.Endpoint, &lastSeen, &n.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if lastSeen.Valid {
		n.LastSeenAt = lastSeen.Time
	}
	return n, err
}

func (r *SQLiteRepository) UpdateNodeEndpoint(id, endpoint string) error {
	query := `UPDATE nodes SET endpoint = ?, last_seen_at = CURRENT_TIMESTAMP WHERE id = ?`
	_, err := r.db.Exec(query, endpoint, id)
	return err
}

func (r *SQLiteRepository) ListPeers(networkID, excludeNodeID string) ([]models.Peer, error) {
	query := `SELECT public_key, ipv4_address, endpoint FROM nodes WHERE network_id = ? AND id != ?`
	rows, err := r.db.Query(query, networkID, excludeNodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var peers []models.Peer
	for rows.Next() {
		var p models.Peer
		if err := rows.Scan(&p.PublicKey, &p.IPv4Address, &p.Endpoint); err != nil {
			return nil, err
		}
		peers = append(peers, p)
	}
	return peers, nil
}

func (r *SQLiteRepository) DeleteNode(id string) error {
	_, err := r.db.Exec(`DELETE FROM nodes WHERE id = ?`, id)
	return err
}

// Enrollment implementation

func (r *SQLiteRepository) GetEnrollmentToken(token string) (*models.EnrollmentToken, error) {
	t := &models.EnrollmentToken{}
	query := `SELECT token, network_id, used, created_at FROM enrollment_tokens WHERE token = ? AND used = 0`
	err := r.db.QueryRow(query, token).Scan(&t.Token, &t.NetworkID, &t.Used, &t.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return t, err
}

func (r *SQLiteRepository) ConsumeToken(token string) error {
	_, err := r.db.Exec(`UPDATE enrollment_tokens SET used = 1 WHERE token = ?`, token)
	return err
}

func (r *SQLiteRepository) CreateEnrollmentToken(t *models.EnrollmentToken) error {
	_, err := r.db.Exec(`INSERT INTO enrollment_tokens (token, network_id) VALUES (?, ?)`, t.Token, t.NetworkID)
	return err
}

func (r *SQLiteRepository) ListEnrollmentTokens() ([]models.EnrollmentToken, error) {
	query := `SELECT token, network_id, used, created_at FROM enrollment_tokens ORDER BY created_at DESC`
	rows, err := r.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []models.EnrollmentToken
	for rows.Next() {
		var t models.EnrollmentToken
		if err := rows.Scan(&t.Token, &t.NetworkID, &t.Used, &t.CreatedAt); err != nil {
			return nil, err
		}
		tokens = append(tokens, t)
	}
	return tokens, nil
}

func (r *SQLiteRepository) DeleteEnrollmentToken(token string) error {
	_, err := r.db.Exec(`DELETE FROM enrollment_tokens WHERE token = ?`, token)
	return err
}

func (r *SQLiteRepository) GetNextAvailableIP(networkID string) (string, error) {
	// Simple logic: get network range, and pick the next IP after the last node
	// This is a placeholder. A real implementation would parse the CIDR.
	var lastIP string
	query := `SELECT ipv4_address FROM nodes WHERE network_id = ? ORDER BY ipv4_address DESC LIMIT 1`
	err := r.db.QueryRow(query, networkID).Scan(&lastIP)
	
	if err == sql.ErrNoRows {
		// Get network range to start
		var ipv4Range string
		err := r.db.QueryRow(`SELECT ipv4_range FROM networks WHERE id = ?`, networkID).Scan(&ipv4Range)
		if err != nil {
			return "", err
		}
		// Return .2 as first IP (placeholder logic)
		return "10.0.0.2", nil 
	}
	
	if err != nil {
		return "", err
	}

	// Increment last IP (extreme simplified placeholder logic)
	return "10.0.0.3", nil 
}

// Sessions implementation

func (r *SQLiteRepository) CreateSession(s *models.Session) error {
	query := `INSERT INTO sessions (token, expires_at) VALUES (?, ?)`
	_, err := r.db.Exec(query, s.Token, s.ExpiresAt)
	return err
}

func (r *SQLiteRepository) GetSession(token string) (*models.Session, error) {
	s := &models.Session{}
	query := `SELECT token, expires_at, created_at FROM sessions WHERE token = ?`
	err := r.db.QueryRow(query, token).Scan(&s.Token, &s.ExpiresAt, &s.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return s, err
}

func (r *SQLiteRepository) DeleteSession(token string) error {
	_, err := r.db.Exec(`DELETE FROM sessions WHERE token = ?`, token)
	return err
}

