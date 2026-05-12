"use client";

import React, { useState } from "react";
import { Sidebar } from "./Sidebar/Sidebar";
import styles from "./LayoutWrapper.module.css";

export default function LayoutWrapper({ children }: { children: React.ReactNode }) {
  const [isCollapsed, setIsCollapsed] = useState(false);

  return (
    <div className={styles.wrapper}>
      <Sidebar isCollapsed={isCollapsed} setIsCollapsed={setIsCollapsed} />
      <main 
        className={styles.main} 
        style={{ 
          marginLeft: isCollapsed ? "var(--sidebar-collapsed-width)" : "var(--sidebar-width)" 
        }}
      >
        <header className={styles.header}>
          {/* Top header content like user profile, breadcrumbs etc. can go here */}
          <div className={styles.headerContent}>
            <h2 className={styles.pageTitle}>Dashboard</h2>
            <div className={styles.userSection}>
              <div className={styles.avatar}>A</div>
            </div>
          </div>
        </header>
        <div className={styles.content}>
          {children}
        </div>
      </main>
    </div>
  );
}
