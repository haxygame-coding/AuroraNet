"use client";

import React, { useEffect, useState, useCallback } from "react";
import { Plus, Trash2, Key, Copy, Check, Shield } from "lucide-react";
import tableStyles from "@/components/Table/Table.module.css";

interface EnrollmentToken {
  token: string;
  network_id: string;
  used: boolean;
  created_at: string;
}

interface Network {
  id: string;
  name: string;
}

export default function TokensPage() {
  const [tokens, setTokens] = useState<EnrollmentToken[]>([]);
  const [networks, setNetworks] = useState<Network[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isCreating, setIsCreating] = useState(false);
  const [selectedNetwork, setSelectedNetwork] = useState("");
  const [copiedToken, setCopiedToken] = useState("");

  const fetchData = useCallback(async () => {
    try {
      const [tokenRes, netRes] = await Promise.all([
        fetch("/api/tokens"),
        fetch("/api/networks")
      ]);
      
      if (tokenRes.ok && netRes.ok) {
        const tokensData = await tokenRes.json();
        const networksData = await netRes.json();
        setTokens(tokensData || []);
        setNetworks(networksData || []);
        if (networksData?.length > 0) {
          setSelectedNetwork(networksData[0].id);
        }
      }
    } catch {
      console.error("Failed to fetch data");
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    let isMounted = true;
    const load = async () => {
      if (isMounted) {
        await fetchData();
      }
    };
    load();
    return () => { isMounted = false; };
  }, [fetchData]);

  const handleCreate = async () => {
    if (!selectedNetwork) return;
    try {
      const response = await fetch("/api/tokens", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ network_id: selectedNetwork }),
      });
      if (response.ok) {
        setIsCreating(false);
        fetchData();
      }
    } catch {
      alert("Failed to create token");
    }
  };

  const handleDelete = async (token: string) => {
    if (!confirm("Are you sure you want to revoke this token?")) return;
    try {
      const response = await fetch(`/api/tokens/${token}`, { method: "DELETE" });
      if (response.ok) {
        setTokens(tokens.filter(t => t.token !== token));
      }
    } catch {
      alert("Failed to delete token");
    }
  };

  const copyToClipboard = (token: string) => {
    navigator.clipboard.writeText(token);
    setCopiedToken(token);
    setTimeout(() => setCopiedToken(""), 2000);
  };

  return (
    <div>
      <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "32px" }}>
        <div>
          <h1 style={{ fontSize: "2rem", marginBottom: "8px" }}>Enrollment Tokens</h1>
          <p style={{ color: "var(--foreground-muted)" }}>Generate one-time tokens to add new nodes to your networks.</p>
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
          {isCreating ? "Cancel" : <><Plus size={20} /> Generate Token</>}
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
          <h3 style={{ marginBottom: "20px" }}>Generate New Token</h3>
          <div style={{ display: "flex", gap: "16px", alignItems: "end" }}>
            <div style={{ display: "flex", flexDirection: "column", gap: "8px", flex: 1 }}>
              <label style={{ fontSize: "0.85rem", color: "var(--foreground-muted)" }}>Select Network</label>
              <select 
                value={selectedNetwork}
                onChange={e => setSelectedNetwork(e.target.value)}
                style={{ 
                  background: "var(--background)", 
                  border: "1px solid var(--border)", 
                  padding: "10px", 
                  borderRadius: "6px",
                  color: "white"
                }}
              >
                {networks.map(n => (
                  <option key={n.id} value={n.id}>{n.name}</option>
                ))}
              </select>
            </div>
            <button 
              onClick={handleCreate}
              style={{ 
                background: "var(--primary)", 
                color: "white", 
                padding: "10px 24px", 
                borderRadius: "6px",
                fontWeight: "600"
              }}
            >
              Generate
            </button>
          </div>
        </div>
      )}

      <div className={tableStyles.container}>
        <table className={tableStyles.table}>
          <thead>
            <tr>
              <th>Token</th>
              <th>Network</th>
              <th>Status</th>
              <th>Created At</th>
              <th style={{ textAlign: "right" }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {tokens.length === 0 ? (
              <tr>
                <td colSpan={5} className={tableStyles.empty}>
                  {isLoading ? "Loading tokens..." : "No enrollment tokens found. Generate one to enroll a new node."}
                </td>
              </tr>
            ) : (
              tokens.map((token) => (
                <tr key={token.token}>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
                      <Key size={18} color="var(--primary)" />
                      <code style={{ background: "rgba(255,255,255,0.05)", padding: "4px 8px", borderRadius: "4px" }}>
                        {token.token.substring(0, 16)}...
                      </code>
                      <button 
                        onClick={() => copyToClipboard(token.token)}
                        style={{ color: "var(--foreground-muted)", hover: { color: "white" } }}
                        title="Copy to clipboard"
                      >
                        {copiedToken === token.token ? <Check size={16} color="#22c55e" /> : <Copy size={16} />}
                      </button>
                    </div>
                  </td>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                      <Shield size={14} color="var(--secondary)" />
                      {networks.find(n => n.id === token.network_id)?.name || "Unknown"}
                    </div>
                  </td>
                  <td>
                    <span className={`${tableStyles.status} ${token.used ? "" : tableStyles.statusActive}`} style={{ background: token.used ? "rgba(255,255,255,0.05)" : undefined, color: token.used ? "var(--foreground-muted)" : undefined }}>
                      {token.used ? "Consumed" : "Active"}
                    </span>
                  </td>
                  <td>{new Date(token.created_at).toLocaleDateString()}</td>
                  <td style={{ textAlign: "right" }}>
                    <button 
                      className={tableStyles.actionBtn}
                      onClick={() => handleDelete(token.token)}
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
