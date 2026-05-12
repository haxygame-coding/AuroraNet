"use client";

import React, { useEffect, useState } from "react";
import { Network, Server, Activity } from "lucide-react";

export default function Home() {
  const [stats, setStats] = useState({ networks: 0, nodes: 0 });
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const fetchStats = async () => {
      try {
        const [netRes, nodeRes] = await Promise.all([
          fetch("/api/networks"),
          fetch("/api/nodes")
        ]);
        
        const networks = await netRes.json();
        const nodes = await nodeRes.json();
        
        setStats({
          networks: networks?.length || 0,
          nodes: nodes?.length || 0
        });
      } catch (err) {
        console.error("Failed to fetch stats", err);
      } finally {
        setIsLoading(false);
      }
    };

    fetchStats();
  }, []);

  return (
    <div>
      <section style={{ marginBottom: "40px" }}>
        <h1 style={{ fontSize: "2rem", marginBottom: "8px" }}>Overview</h1>
        <p style={{ color: "var(--foreground-muted)" }}>Welcome to your Auroranet control plane.</p>
      </section>

      <div style={{ 
        display: "grid", 
        gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))", 
        gap: "24px" 
      }}>
        <div style={{ 
          background: "var(--surface)", 
          padding: "24px", 
          borderRadius: "12px", 
          border: "1px solid var(--border)",
          position: "relative",
          overflow: "hidden"
        }}>
          <div style={{ position: "absolute", right: "-10px", top: "-10px", opacity: 0.05 }}>
            <Network size={120} />
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "16px" }}>
            <div style={{ padding: "8px", background: "rgba(139, 92, 246, 0.1)", borderRadius: "8px", color: "var(--primary)" }}>
              <Network size={20} />
            </div>
            <h3 style={{ fontSize: "1rem", fontWeight: "600" }}>Networks</h3>
          </div>
          <p style={{ fontSize: "2.5rem", fontWeight: "bold" }}>{isLoading ? "..." : stats.networks}</p>
          <p style={{ color: "var(--foreground-muted)", marginTop: "8px", fontSize: "0.9rem" }}>Active mesh networks</p>
        </div>

        <div style={{ 
          background: "var(--surface)", 
          padding: "24px", 
          borderRadius: "12px", 
          border: "1px solid var(--border)",
          position: "relative",
          overflow: "hidden"
        }}>
          <div style={{ position: "absolute", right: "-10px", top: "-10px", opacity: 0.05 }}>
            <Server size={120} />
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "16px" }}>
            <div style={{ padding: "8px", background: "rgba(6, 182, 212, 0.1)", borderRadius: "8px", color: "var(--secondary)" }}>
              <Server size={20} />
            </div>
            <h3 style={{ fontSize: "1rem", fontWeight: "600" }}>Nodes</h3>
          </div>
          <p style={{ fontSize: "2.5rem", fontWeight: "bold" }}>{isLoading ? "..." : stats.nodes}</p>
          <p style={{ color: "var(--foreground-muted)", marginTop: "8px", fontSize: "0.9rem" }}>Connected devices</p>
        </div>

        <div style={{ 
          background: "var(--surface)", 
          padding: "24px", 
          borderRadius: "12px", 
          border: "1px solid var(--border)",
          position: "relative",
          overflow: "hidden"
        }}>
          <div style={{ position: "absolute", right: "-10px", top: "-10px", opacity: 0.05 }}>
            <Activity size={120} />
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "16px" }}>
            <div style={{ padding: "8px", background: "rgba(217, 70, 239, 0.1)", borderRadius: "8px", color: "var(--accent)" }}>
              <Activity size={20} />
            </div>
            <h3 style={{ fontSize: "1rem", fontWeight: "600" }}>Traffic</h3>
          </div>
          <p style={{ fontSize: "2.5rem", fontWeight: "bold" }}>0 B/s</p>
          <p style={{ color: "var(--foreground-muted)", marginTop: "8px", fontSize: "0.9rem" }}>Real-time throughput</p>
        </div>
      </div>
    </div>
  );
}
