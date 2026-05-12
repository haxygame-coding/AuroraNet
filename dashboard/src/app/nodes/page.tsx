"use client";

import React, { useEffect, useState, useCallback } from "react";
import { Trash2, Server, Shield } from "lucide-react";
import tableStyles from "@/components/Table/Table.module.css";

interface Node {
  id: string;
  network_id: string;
  name: string;
  public_key: string;
  ipv4_address: string;
  created_at: string;
}

export default function NodesPage() {
  const [nodes, setNodes] = useState<Node[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState("");

  const fetchNodes = useCallback(async () => {
    try {
      const response = await fetch("/api/nodes");
      if (response.ok) {
        const data = await response.json();
        setNodes(data || []);
      } else {
        setError("Failed to fetch nodes");
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
      if (isMounted) {
        await fetchNodes();
      }
    };
    load();
    return () => { isMounted = false; };
  }, [fetchNodes]);

  const handleDelete = async (id: string) => {
    if (!confirm("Are you sure you want to remove this node?")) return;
    
    try {
      const response = await fetch(`/api/nodes/${id}`, { method: "DELETE" });
      if (response.ok) {
        setNodes(nodes.filter(n => n.id !== id));
      }
    } catch {
      alert("Failed to delete node");
    }
  };

  return (
    <div>
      <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "32px" }}>
        <div>
          <h1 style={{ fontSize: "2rem", marginBottom: "8px" }}>Nodes</h1>
          <p style={{ color: "var(--foreground-muted)" }}>Connected devices in your mesh.</p>
        </div>
      </header>

      {error && <div style={{ color: "#ef4444", marginBottom: "20px" }}>{error}</div>}

      <div className={tableStyles.container}>
        <table className={tableStyles.table}>
          <thead>
            <tr>
              <th>Node Name</th>
              <th>IP Address</th>
              <th>Network ID</th>
              <th>Status</th>
              <th style={{ textAlign: "right" }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {nodes.length === 0 ? (
              <tr>
                <td colSpan={5} className={tableStyles.empty}>
                  {isLoading ? "Loading nodes..." : "No nodes found. Enroll a device to see it here."}
                </td>
              </tr>
            ) : (
              nodes.map((node) => (
                <tr key={node.id}>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
                      <Server size={18} color="var(--secondary)" />
                      <div>
                        <div style={{ fontWeight: "500" }}>{node.name}</div>
                        <div style={{ fontSize: "0.75rem", color: "var(--foreground-muted)", fontFamily: "monospace" }}>
                          {node.id.substring(0, 8)}...
                        </div>
                      </div>
                    </div>
                  </td>
                  <td><code>{node.ipv4_address}</code></td>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: "6px", fontSize: "0.85rem" }}>
                      <Shield size={14} />
                      {node.network_id.substring(0, 8)}...
                    </div>
                  </td>
                  <td>
                    <span className={`${tableStyles.status} ${tableStyles.statusActive}`}>
                      Online
                    </span>
                  </td>
                  <td style={{ textAlign: "right" }}>
                    <button 
                      className={tableStyles.actionBtn}
                      onClick={() => handleDelete(node.id)}
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
