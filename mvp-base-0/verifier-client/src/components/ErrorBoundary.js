import React from 'react';

/**
 * ErrorBoundary
 * Wraps any subtree and catches uncaught render/lifecycle errors.
 *
 * Usage:
 *   <ErrorBoundary>
 *     <YourComponent />
 *   </ErrorBoundary>
 *
 * Optional props:
 *   fallback  – custom ReactElement to show in place of the broken tree
 *   onError   – callback(error, info) for external logging (e.g. Sentry)
 */
class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null, info: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, info) {
    this.setState({ info });
    if (typeof this.props.onError === 'function') {
      this.props.onError(error, info);
    } else {
      // Default: log to console so the trace is still visible in DevTools.
      console.error('[ErrorBoundary] Caught an unhandled error:', error, info);
    }
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null, info: null });
  };

  render() {
    const { hasError, error } = this.state;
    const { fallback, children } = this.props;

    if (!hasError) return children;

    // Custom fallback provided by the parent
    if (fallback) return fallback;

    // Default built-in fallback UI
    return (
      <div style={styles.container}>
        <div style={styles.card}>
          <h2 style={styles.heading}>Something went wrong</h2>
          <p style={styles.message}>
            An unexpected error occurred. You can try reloading the page or
            click the button below to reset this section.
          </p>
          {error && (
            <details style={styles.details}>
              <summary style={styles.summary}>Error details</summary>
              <pre style={styles.pre}>{error.toString()}</pre>
            </details>
          )}
          <button style={styles.button} onClick={this.handleReset}>
            Try Again
          </button>
        </div>
      </div>
    );
  }
}

// ---------------------------------------------------------------------------
// Inline styles – Mono technical theme
// ---------------------------------------------------------------------------
const styles = {
  container: {
    display:        'flex',
    alignItems:     'center',
    justifyContent: 'center',
    minHeight:      '100vh',
    padding:        '32px',
    background:     '#ffffff',
  },
  card: {
    background:   'transparent',
    padding:      '64px 48px',
    maxWidth:     '520px',
    width:        '100%',
    textAlign:    'center',
  },
  heading: {
    color:         '#09090b',
    marginTop:     0,
    marginBottom:  '16px',
    fontSize:      '1.125rem',
    fontWeight:    '600',
    fontFamily:    '"JetBrains Mono", "SF Mono", Monaco, monospace',
    letterSpacing: '-0.02em',
  },
  message: {
    color:        '#71717a',
    marginBottom: '32px',
    lineHeight:   '1.7',
    fontSize:     '0.9375rem',
    fontFamily:   '"JetBrains Mono", "SF Mono", Monaco, monospace',
  },
  details: {
    textAlign:    'left',
    marginBottom: '32px',
    background:   '#f4f4f5',
    padding:      '24px',
  },
  summary: {
    cursor:     'pointer',
    color:      '#71717a',
    fontSize:   '0.8125rem',
    userSelect: 'none',
    fontWeight: '500',
    fontFamily: '"JetBrains Mono", "SF Mono", Monaco, monospace',
  },
  pre: {
    color:         '#ef4444',
    fontSize:      '0.8125rem',
    overflow:      'auto',
    margin:        '16px 0 0',
    whiteSpace:    'pre-wrap',
    wordBreak:     'break-word',
    fontFamily:    '"JetBrains Mono", "SF Mono", Monaco, monospace',
    lineHeight:    '1.7',
  },
  button: {
    background:   '#09090b',
    color:        '#ffffff',
    border:       'none',
    padding:      '18px 32px',
    cursor:       'pointer',
    fontSize:     '0.9375rem',
    fontWeight:   '500',
    fontFamily:   '"JetBrains Mono", "SF Mono", Monaco, monospace',
    transition:   'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
  },
};

export default ErrorBoundary;
