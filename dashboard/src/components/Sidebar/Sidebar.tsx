"use client";

import React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { 
  LayoutDashboard, 
  Network, 
  Server, 
  Key, 
  Settings, 
  ChevronLeft, 
  ChevronRight,
  ShieldCheck,
  LogOut
} from "lucide-react";
import styles from "./Sidebar.module.css";

interface SidebarProps {
  isCollapsed: boolean;
  setIsCollapsed: (value: boolean) => void;
}

const navItems = [
  { href: "/", label: "Overview", icon: LayoutDashboard },
  { href: "/networks", label: "Networks", icon: Network },
  { href: "/nodes", label: "Nodes", icon: Server },
  { href: "/tokens", label: "Enrollment Tokens", icon: Key },
  { href: "/settings", label: "Settings", icon: Settings },
];

export function Sidebar({ isCollapsed, setIsCollapsed }: SidebarProps) {
  const pathname = usePathname();
  const router = useRouter();

  const handleLogout = async () => {
    try {
      await fetch("/api/logout", { method: "POST" });
      router.push("/login");
      router.refresh();
    } catch {
      console.error("Logout failed");
    }
  };

  return (
    <aside className={`${styles.sidebar} ${isCollapsed ? styles.collapsed : ""}`}>
      <div className={styles.header}>
        <div className={styles.logo}>
          <ShieldCheck size={20} color="white" />
        </div>
        <span className={styles.title}>AURORANET</span>
      </div>

      <nav className={styles.nav}>
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = pathname === item.href;
          
          return (
            <Link 
              key={item.href} 
              href={item.href}
              className={`${styles.navItem} ${isActive ? styles.active : ""}`}
            >
              <Icon size={20} />
              <span className={styles.navLabel}>{item.label}</span>
            </Link>
          );
        })}
      </nav>

      <div className={styles.footer}>
        <button 
          className={styles.navItem} 
          onClick={handleLogout}
          style={{ width: "100%", border: "none", background: "none", cursor: "pointer" }}
        >
          <LogOut size={20} />
          <span className={styles.navLabel}>Logout</span>
        </button>
        <button 
          className={styles.toggleBtn}
          onClick={() => setIsCollapsed(!isCollapsed)}
          aria-label={isCollapsed ? "Expand sidebar" : "Collapse sidebar"}
        >
          {isCollapsed ? <ChevronRight size={20} /> : <ChevronLeft size={20} />}
        </button>
      </div>
    </aside>
  );
}
