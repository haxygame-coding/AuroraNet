"use client";

import React, { useEffect, useState, useCallback } from "react";
import { Plus, Trash2, Globe } from "lucide-react";
import tableStyles from "@/components/Table/Table.module.css";

interface Network {
  id: string;
  name: string;
  ipv4_range: string;
  created_at: string;
}

export default function NetworksPage() {
  const [networks, setNetworks] = useState<Network[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState("");
  const [isCreating, setIsCreating] = useState(false);
  const [newNetwork, setNewNetwork] = useState({ name: "", ipv4_range: "10.0.0.0/24" });

  const fetchNetworks = useCallback(async () => {
    try {
      const response = await fetch("/api/networks");
      if (response.ok) {
        const data = await response.json();
        setNetworks(data || []);
      } else {
        setError("Failed to fetch networks");
      }
    } catch {
      setError("Connection error");
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    let isMounted = true;
    const load = async () => {
      await fetchNetworks();
    };
    if (isMounted) {
      load();
    }
    return () => { isMounted = false; };
  }, [fetchNetworks]);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const response = await fetch("/api/networks", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(newNetwork),
      });
      if (response.ok) {
        setIsCreating(false);
        setNewNetwork({ name: "", ipv4_range: "10.0.0.0/24" });
        fetchNetworks();
      } else {
        alert("Failed to create network");
      }
    } catch {
      alert("Error connecting to server");
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Are you sure you want to delete this network?")) return;
    
    try {
      const response = await fetch(`/api/networks/${id}`, { method: "DELETE" });
      if (response.ok) {
        setNetworks(networks.filter(n => n.id !== id));
      }
    } catch {
      alert("Failed to delete network");
    }
  };

  return (
    <div>
      <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "32px" }}>
        <div>
          <h1 style={{ fontSize: "2rem", marginBottom: "8px" }}>Networks</h1>
          <p style={{ color: "var(--foreground-muted)" }}>Manage your virtual mesh networks.</p>
        </div>
        <button 
          onClick={() => setIsCreating(!isCreating)}
          style={{ 
            background: isCreating ? "var(--surface)" : "var(--primary)", 
            color: isCreating ? "var(--foreground)" : "white", 
            padding: "10px 20px", 
            borderRadius: "8px", 
            display: "flex", 
            alignItems: "center", 
            gap: "8px",
            fontWeight: "600",
            border: isCreating ? "1px solid var(--border)" : "none"
          }}
        >
          {isCreating ? "Cancel" : <><Plus size={20} /> Create Network</>}
        </button>
      </header>

      {isCreating && (
        <div style={{ 
          background: "var(--surface)", 
          padding: "24px", 
          borderRadius: "12px", 
          border: "1px solid var(--border)",
          marginBottom: "32px"
        }}>
          <h3 style={{ marginBottom: "20px" }}>New Network</h3>
          <form onSubmit={handleCreate} style={{ display: "grid", gridTemplateColumns: "1fr 1fr auto", gap: "16px", alignItems: "end" }}>
            <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
              <label style={{ fontSize: "0.85rem", color: "var(--foreground-muted)" }}>Network Name</label>
              <input 
                type="text" 
                placeholder="e.g. My Home Lab"
                required
                value={newNetwork.name}
                onChange={e => setNewNetwork({...newNetwork, name: e.target.value})}
                style={{ 
                  background: "var(--background)", 
                  border: "1px solid var(--border)", 
                  padding: "10px", 
                  borderRadius: "6px",
                  color: "white"
                }}
              />
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
              <label style={{ fontSize: "0.85rem", color: "var(--foreground-muted)" }}>IPv4 Range (CIDR)</label>
              <input 
                type="text" 
                placeholder="10.0.0.0/24"
                required
                value={newNetwork.ipv4_range}
                onChange={e => setNewNetwork({...newNetwork, ipv4_range: e.target.value})}
                style={{ 
                  background: "var(--background)", 
                  border: "1px solid var(--border)", 
                  padding: "10px", 
                  borderRadius: "6px",
                  color: "white"
                }}
              />
            </div>
            <button type="submit" style={{ 
              background: "var(--primary)", 
              color: "white", 
              padding: "10px 24px", 
              borderRadius: "6px",
              fontWeight: "600"
            }}>
              Confirm
            </button>
          </form>
        </div>
      )}

      {error && <div style={{ color: "#ef4444", marginBottom: "20px" }}>{error}</div>}

      <div className={tableStyles.container}>
        <table className={tableStyles.table}>
          <thead>
            <tr>
              <th>Name</th>
              <th>IPv4 Range</th>
              <th>Created At</th>
              <th style={{ textAlign: "right" }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {networks.length === 0 ? (
              <tr>
                <td colSpan={4} className={tableStyles.empty}>
                  {isLoading ? "Loading networks..." : "No networks found. Create one to get started."}
                </td>
              </tr>
            ) : (
              networks.map((network) => (
                <tr key={network.id}>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
                      <Globe size={18} color="var(--primary)" />
                      <span style={{ fontWeight: "500" }}>{network.name}</span>
                    </div>
                  </td>
                  <td><code>{network.ipv4_range}</code></td>
                  <td>{new Date(network.created_at).toLocaleDateString()}</td>
                  <td style={{ textAlign: "right" }}>
                    <button 
                      className={tableStyles.actionBtn}
                      onClick={() => handleDelete(network.id)}
                    >
                      <Trash2 size={18} />
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
