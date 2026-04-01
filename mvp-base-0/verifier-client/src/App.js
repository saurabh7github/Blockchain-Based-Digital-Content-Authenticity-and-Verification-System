import React, { useState } from "react";
import { BrowserRouter, Routes, Route, NavLink, Navigate } from "react-router-dom";
import IssueDocument  from "./components/IssueDocument";
import VerifyDocument from "./components/VerifyDocument";
import RevokeDocument from "./components/RevokeDocument";
import ErrorBoundary  from "./components/ErrorBoundary";
import "./App.css";

// ---------------------------------------------------------------------------
// Inner layout — has access to router location for active-tab detection
// ---------------------------------------------------------------------------
function Layout({ network, setNetwork }) {
  return (
    <div className="app-container">
      <header className="app-header">
        <div className="header-top">
          <div className="header-branding">
            <h1 className="app-title">DocVerify</h1>
            <p className="app-subtitle">Blockchain-powered document authenticity &amp; verification</p>
          </div>
        </div>

        {/* Network selector */}
        <div className="network-toggle-row">
            <span className="network-toggle-label">Ledger:</span>
            <div className="network-toggle">
              <button
                className={`network-btn ${network === "ethereum" ? "network-active" : ""}`}
                onClick={() => setNetwork("ethereum")}
              >
                Ethereum Sepolia
              </button>
              <button
                className={`network-btn ${network === "fabric" ? "network-active" : ""}`}
                onClick={() => setNetwork("fabric")}
              >
                Hyperledger Fabric
              </button>
            </div>
          </div>
      </header>

      <nav className="tab-bar">
        <NavLink
          to="/issue"
          className={({ isActive }) => `tab-btn ${isActive ? "tab-active" : ""}`}
        >
          Issue Document
        </NavLink>
        <NavLink
          to="/verify"
          className={({ isActive }) => `tab-btn ${isActive ? "tab-active" : ""}`}
        >
          Verify Document
        </NavLink>
        <NavLink
          to="/admin"
          className={({ isActive }) => `tab-btn ${isActive ? "tab-active" : ""}`}
        >
          Admin
        </NavLink>
      </nav>

      <main>
        <ErrorBoundary>
          <Routes>
            <Route path="/issue"  element={<IssueDocument  network={network} />} />
            <Route path="/verify" element={<VerifyDocument network={network} />} />
            <Route path="/admin"  element={<RevokeDocument network={network} />} />
            {/* Redirect root → /issue */}
            <Route path="/"       element={<Navigate to="/issue" replace />} />
            {/* Catch-all */}
            <Route path="*"       element={<Navigate to="/issue" replace />} />
          </Routes>
        </ErrorBoundary>
      </main>

      <footer className="app-footer">
        {network === "fabric"
          ? "Hyperledger Fabric"
          : "Ethereum Sepolia Testnet"
        } &bull; SHA-256 &bull; DocVerifier
      </footer>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Root — provides router context and top-level network state
// ---------------------------------------------------------------------------
function App() {
  const [network, setNetwork] = useState("ethereum"); // "ethereum" | "fabric"

  return (
    <BrowserRouter>
      <Layout network={network} setNetwork={setNetwork} />
    </BrowserRouter>
  );
}

export default App;


