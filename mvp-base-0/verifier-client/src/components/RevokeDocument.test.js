import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import axios from 'axios';
import RevokeDocument from './RevokeDocument';

// Mock axios
jest.mock('axios');
const mockedAxios = axios;

// Mock ethers.js
const mockContract = {
  revokeDocument: jest.fn().mockResolvedValue({
    hash: '0xtxhash123',
    wait: jest.fn().mockResolvedValue({})
  }),
  pauseContract: jest.fn().mockResolvedValue({
    hash: '0xtxhash456',
    wait: jest.fn().mockResolvedValue({})
  }),
  unpauseContract: jest.fn().mockResolvedValue({
    hash: '0xtxhash789',
    wait: jest.fn().mockResolvedValue({})
  }),
  transferOwnership: jest.fn().mockResolvedValue({
    hash: '0xtxhashABC',
    wait: jest.fn().mockResolvedValue({})
  }),
};

jest.mock('ethers', () => ({
  ethers: {
    BrowserProvider: jest.fn(),
    Contract: jest.fn(() => mockContract),
    getBytes: jest.fn(),
    keccak256: jest.fn(() => '0xmockedhash1234567890abcdef1234567890abcdef1234567890abcdef1234567890'),
  },
}));

// Mock getSignerOnSepolia
jest.mock('../lib/ethereum', () => ({
  getSignerOnSepolia: jest.fn().mockResolvedValue({}),
}));

describe('RevokeDocument', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    // Default successful document lookup response
    mockedAxios.get = jest.fn().mockResolvedValue({
      data: {
        docHash: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        fileName: 'test-document.pdf',
        aiScore: 12,
        aiProvider: 'mock',
        isAuthentic: true,
        issuer: 'Org1MSP',
        timestamp: '2026-03-25T10:00:00Z',
        revoked: false,
        network: 'fabric'
      },
    });
  });

  it('renders lookup section', () => {
    render(<RevokeDocument network="fabric" />);

    expect(screen.getByText(/revoke a document/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/choose file/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /look up document/i })).toBeInTheDocument();
  });

  it('shows preview after document lookup', async () => {
    render(<RevokeDocument network="fabric" />);

    const file = new File(['test content'], 'test.pdf', { type: 'application/pdf' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /look up document/i }));

    await waitFor(() => {
      expect(screen.getByText(/test-document.pdf/i)).toBeInTheDocument();
      expect(screen.getByText(/org1msp/i)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /revoke document/i })).toBeInTheDocument();
    });
  });

  it('displays issuer and timestamp in preview', async () => {
    render(<RevokeDocument network="fabric" />);

    mockedAxios.get = jest.fn().mockResolvedValue({
      data: {
        docHash: '0xtest123',
        fileName: 'preview-test.pdf',
        issuer: 'Org2MSP',
        timestamp: '2026-03-20T15:30:00Z',
        revoked: false,
        network: 'fabric'
      },
    });

    const file = new File(['test'], 'test.pdf', { type: 'application/pdf' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /look up document/i }));

    await waitFor(() => {
      expect(screen.getByText(/org2msp/i)).toBeInTheDocument();
      expect(screen.getByText(/march 20, 2026/i)).toBeInTheDocument();
    });
  });

  it('shows admin login for Fabric mode', () => {
    render(<RevokeDocument network="fabric" />);

    expect(screen.getByText(/admin login/i)).toBeInTheDocument();
    expect(screen.getByPlaceholderText(/username/i)).toBeInTheDocument();
    expect(screen.getByPlaceholderText(/password/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /login/i })).toBeInTheDocument();
  });

  it('handles admin login successfully', async () => {
    render(<RevokeDocument network="fabric" />);

    mockedAxios.post = jest.fn().mockResolvedValue({
      data: { token: 'mock-jwt-token-123456789' }
    });

    const usernameInput = screen.getByPlaceholderText(/username/i);
    const passwordInput = screen.getByPlaceholderText(/password/i);
    const loginButton = screen.getByRole('button', { name: /login/i });

    fireEvent.change(usernameInput, { target: { value: 'admin' } });
    fireEvent.change(passwordInput, { target: { value: 'password' } });
    fireEvent.click(loginButton);

    await waitFor(() => {
      expect(mockedAxios.post).toHaveBeenCalledWith(
        'http://localhost:5000/api/auth/login',
        { username: 'admin', password: 'password' }
      );
      expect(screen.getByText(/logged in as admin/i)).toBeInTheDocument();
    });
  });

  it('handles admin login failure', async () => {
    render(<RevokeDocument network="fabric" />);

    mockedAxios.post = jest.fn().mockRejectedValue({
      response: {
        status: 401,
        data: { error: 'Invalid credentials' }
      }
    });

    const usernameInput = screen.getByPlaceholderText(/username/i);
    const passwordInput = screen.getByPlaceholderText(/password/i);
    const loginButton = screen.getByRole('button', { name: /login/i });

    fireEvent.change(usernameInput, { target: { value: 'admin' } });
    fireEvent.change(passwordInput, { target: { value: 'wrongpass' } });
    fireEvent.click(loginButton);

    await waitFor(() => {
      expect(screen.getByText(/invalid credentials/i)).toBeInTheDocument();
    });
  });

  it('displays success message after Fabric revocation', async () => {
    render(<RevokeDocument network="fabric" />);

    // Mock successful login first
    mockedAxios.post = jest.fn()
      .mockResolvedValueOnce({ data: { token: 'jwt-token' } }) // Login
      .mockResolvedValueOnce({ data: { success: true, revoked: true } }); // Revoke

    // Login
    fireEvent.change(screen.getByPlaceholderText(/username/i), { target: { value: 'admin' } });
    fireEvent.change(screen.getByPlaceholderText(/password/i), { target: { value: 'password' } });
    fireEvent.click(screen.getByRole('button', { name: /login/i }));

    await waitFor(() => {
      expect(screen.getByText(/logged in/i)).toBeInTheDocument();
    });

    // Lookup document
    const file = new File(['test'], 'test.pdf', { type: 'application/pdf' });
    fireEvent.change(screen.getByLabelText(/choose file/i), { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /look up document/i }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /revoke document/i })).toBeInTheDocument();
    });

    // Revoke document
    fireEvent.click(screen.getByRole('button', { name: /revoke document/i }));

    await waitFor(() => {
      expect(mockedAxios.post).toHaveBeenCalledWith(
        'http://localhost:5000/api/fabric/revoke',
        { docHash: expect.stringMatching(/0x[a-f0-9]{64}/) },
        { headers: { Authorization: 'Bearer jwt-token' } }
      );
      expect(screen.getByText(/revoked successfully on fabric/i)).toBeInTheDocument();
    });
  });

  it('requires admin login for Fabric revocation', async () => {
    render(<RevokeDocument network="fabric" />);

    // Lookup document without logging in
    const file = new File(['test'], 'test.pdf', { type: 'application/pdf' });
    fireEvent.change(screen.getByLabelText(/choose file/i), { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /look up document/i }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /revoke document/i })).toBeInTheDocument();
    });

    // Try to revoke without login
    fireEvent.click(screen.getByRole('button', { name: /revoke document/i }));

    await waitFor(() => {
      expect(screen.getByText(/please log in as admin/i)).toBeInTheDocument();
    });
  });

  it('handles Fabric authentication errors during revocation', async () => {
    render(<RevokeDocument network="fabric" />);

    // Mock successful login
    mockedAxios.post = jest.fn()
      .mockResolvedValueOnce({ data: { token: 'jwt-token' } }) // Login
      .mockRejectedValueOnce({ // Revoke fails with auth error
        response: {
          status: 401,
          data: { error: 'Token expired' }
        }
      });

    // Login first
    fireEvent.change(screen.getByPlaceholderText(/username/i), { target: { value: 'admin' } });
    fireEvent.change(screen.getByPlaceholderText(/password/i), { target: { value: 'password' } });
    fireEvent.click(screen.getByRole('button', { name: /login/i }));

    await waitFor(() => {
      expect(screen.getByText(/logged in/i)).toBeInTheDocument();
    });

    // Lookup and attempt revoke
    const file = new File(['test'], 'test.pdf', { type: 'application/pdf' });
    fireEvent.change(screen.getByLabelText(/choose file/i), { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /look up document/i }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /revoke document/i })).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /revoke document/i }));

    await waitFor(() => {
      expect(screen.getByText(/authentication failed/i)).toBeInTheDocument();
    });
  });

  it('shows MetaMask UI for Ethereum mode', () => {
    render(<RevokeDocument network="ethereum" />);

    // Should not show admin login
    expect(screen.queryByText(/admin login/i)).not.toBeInTheDocument();

    // Should show MetaMask connect button or similar Ethereum-specific UI
    // Note: The exact UI depends on MetaMask connection state
    expect(screen.getByText(/revoke a document.*ethereum/i)).toBeInTheDocument();
  });

  it('handles MetaMask revocation for Ethereum', async () => {
    render(<RevokeDocument network="ethereum" />);

    // Lookup document first
    const file = new File(['test'], 'test.pdf', { type: 'application/pdf' });
    fireEvent.change(screen.getByLabelText(/choose file/i), { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /look up document/i }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /revoke document/i })).toBeInTheDocument();
    });

    // Mock successful MetaMask transaction
    mockContract.revokeDocument = jest.fn().mockResolvedValue({
      hash: '0xethereumtxhash123',
      wait: jest.fn().mockResolvedValue({})
    });

    fireEvent.click(screen.getByRole('button', { name: /revoke document/i }));

    await waitFor(() => {
      expect(mockContract.revokeDocument).toHaveBeenCalled();
      expect(screen.getByText(/revoked successfully/i)).toBeInTheDocument();
      expect(screen.getByText(/0xethereumtxhash123/)).toBeInTheDocument();
    });
  });

  it('shows contract controls for Ethereum mode only', () => {
    // Test Ethereum mode shows contract controls
    render(<RevokeDocument network="ethereum" />);

    expect(screen.getByText(/contract controls/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /pause issuance/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /unpause issuance/i })).toBeInTheDocument();

    // Test Fabric mode does NOT show contract controls
    const { rerender } = render(<RevokeDocument network="fabric" />);
    rerender(<RevokeDocument network="fabric" />);

    expect(screen.queryByText(/contract controls/i)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /pause issuance/i })).not.toBeInTheDocument();
  });

  it('displays confirmation warning before revoke', async () => {
    render(<RevokeDocument network="fabric" />);

    // Login and lookup document
    mockedAxios.post = jest.fn().mockResolvedValue({ data: { token: 'jwt-token' } });

    fireEvent.change(screen.getByPlaceholderText(/username/i), { target: { value: 'admin' } });
    fireEvent.change(screen.getByPlaceholderText(/password/i), { target: { value: 'password' } });
    fireEvent.click(screen.getByRole('button', { name: /login/i }));

    await waitFor(() => {
      expect(screen.getByText(/logged in/i)).toBeInTheDocument();
    });

    const file = new File(['test'], 'test.pdf', { type: 'application/pdf' });
    fireEvent.change(screen.getByLabelText(/choose file/i), { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /look up document/i }));

    await waitFor(() => {
      expect(screen.getByText(/this action is irreversible/i)).toBeInTheDocument();
      expect(screen.getByText(/⚠/)).toBeInTheDocument();
    });
  });

  it('handles document not found error', async () => {
    render(<RevokeDocument network="fabric" />);

    mockedAxios.get = jest.fn().mockRejectedValue({
      response: {
        status: 404,
        data: { error: 'Document not found' }
      }
    });

    const file = new File(['nonexistent'], 'missing.pdf', { type: 'application/pdf' });
    fireEvent.change(screen.getByLabelText(/choose file/i), { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /look up document/i }));

    await waitFor(() => {
      expect(screen.getByText(/document not found/i)).toBeInTheDocument();
    });
  });
});