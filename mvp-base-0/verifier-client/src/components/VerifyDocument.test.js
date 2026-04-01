import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import axios from 'axios';
import VerifyDocument from './VerifyDocument';

// Mock axios
jest.mock('axios');
const mockedAxios = axios;

// Mock ethers.js
jest.mock('ethers', () => ({
  ethers: {
    BrowserProvider: jest.fn(),
    Contract: jest.fn(() => ({
      issueTimestamps: jest.fn().mockResolvedValue(1640995200), // Mock timestamp
      documentHashes: jest.fn().mockResolvedValue('0xmockissuer'),
      isRevoked: jest.fn().mockResolvedValue(false),
    })),
    getBytes: jest.fn(),
    keccak256: jest.fn(() => '0xmockedhash1234567890abcdef1234567890abcdef1234567890abcdef1234567890'),
  },
}));

describe('VerifyDocument', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    // Default successful API response for document lookup
    mockedAxios.get = jest.fn().mockResolvedValue({
      data: {
        docHash: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        fileName: 'test-document.pdf',
        aiScore: 12,
        aiProvider: 'mock',
        isAuthentic: true,
        ipfsCid: 'QmTest123456789',
        createdAt: '2026-03-25T10:00:00Z',
        issuer: 'Org1MSP',
        timestamp: '2026-03-25T10:00:00Z',
        revoked: false,
        network: 'fabric'
      },
    });
  });

  it('renders file input and hash input modes', () => {
    render(<VerifyDocument network="fabric" />);

    expect(screen.getByLabelText(/choose file/i)).toBeInTheDocument();
    expect(screen.getByPlaceholderText(/enter document hash/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /look up/i })).toBeInTheDocument();
  });

  it('switches between file and hash input modes', () => {
    render(<VerifyDocument network="fabric" />);

    const fileTab = screen.getByText(/upload file/i);
    const hashTab = screen.getByText(/paste hash/i);

    // Initially on file tab
    expect(screen.getByLabelText(/choose file/i)).toBeVisible();

    // Switch to hash tab
    fireEvent.click(hashTab);
    expect(screen.getByPlaceholderText(/enter document hash/i)).toBeVisible();

    // Switch back to file tab
    fireEvent.click(fileTab);
    expect(screen.getByLabelText(/choose file/i)).toBeVisible();
  });

  it('computes hash locally for file input', async () => {
    render(<VerifyDocument network="fabric" />);

    const file = new File(['test content'], 'test.txt', { type: 'text/plain' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(mockedAxios.get).toHaveBeenCalledWith(
        'http://localhost:5000/api/fabric/document/0xmockedhash1234567890abcdef1234567890abcdef1234567890abcdef1234567890'
      );
    });
  });

  it('queries Fabric API for Fabric network', async () => {
    render(<VerifyDocument network="fabric" />);

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    // Switch to hash input mode
    fireEvent.click(hashTabButton);

    fireEvent.change(hashInput, {
      target: { value: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(mockedAxios.get).toHaveBeenCalledWith(
        'http://localhost:5000/api/fabric/document/0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890'
      );
    });
  });

  it('queries Ethereum API for Ethereum network', async () => {
    render(<VerifyDocument network="ethereum" />);

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    fireEvent.click(hashTabButton);
    fireEvent.change(hashInput, {
      target: { value: '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(mockedAxios.get).toHaveBeenCalledWith(
        'http://localhost:5000/api/document/0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      );
    });
  });

  it('displays document metadata correctly', async () => {
    render(<VerifyDocument network="fabric" />);

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    fireEvent.click(hashTabButton);
    fireEvent.change(hashInput, {
      target: { value: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(screen.getByText(/test-document.pdf/i)).toBeInTheDocument();
      expect(screen.getByText(/ai score: 12/i)).toBeInTheDocument();
      expect(screen.getByText(/org1msp/i)).toBeInTheDocument();
      expect(screen.getByText(/hyperledger fabric/i)).toBeInTheDocument();
    });
  });

  it('shows error for non-existent documents', async () => {
    render(<VerifyDocument network="fabric" />);

    mockedAxios.get = jest.fn().mockRejectedValue({
      response: {
        status: 404,
        data: { error: 'No document found for this hash' }
      },
    });

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    fireEvent.click(hashTabButton);
    fireEvent.change(hashInput, {
      target: { value: '0xnonexistent1234567890abcdef1234567890abcdef1234567890abcdef123456' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(screen.getByText(/no document found/i)).toBeInTheDocument();
    });
  });

  it('displays revoked status prominently', async () => {
    render(<VerifyDocument network="fabric" />);

    mockedAxios.get = jest.fn().mockResolvedValue({
      data: {
        docHash: '0xrevoked123',
        fileName: 'revoked-doc.pdf',
        aiScore: 5,
        isAuthentic: true,
        issuer: 'Org1MSP',
        timestamp: '2026-03-25T10:00:00Z',
        revoked: true,
        network: 'fabric'
      },
    });

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    fireEvent.click(hashTabButton);
    fireEvent.change(hashInput, {
      target: { value: '0xrevoked123' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(screen.getByText(/revoked/i)).toBeInTheDocument();
      expect(screen.getByText(/⚠/)).toBeInTheDocument();
    });
  });

  it('shows loading state during lookup', async () => {
    render(<VerifyDocument network="fabric" />);

    let resolveApiCall;
    mockedAxios.get = jest.fn().mockReturnValue(
      new Promise((resolve) => {
        resolveApiCall = resolve;
      })
    );

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    fireEvent.click(hashTabButton);
    fireEvent.change(hashInput, {
      target: { value: '0xtest123' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    // Should show loading
    await waitFor(() => {
      expect(screen.getByText(/looking up/i)).toBeInTheDocument();
    });

    // Resolve the API call
    resolveApiCall({
      data: {
        docHash: '0xtest123',
        fileName: 'test.pdf',
        aiScore: 10,
        issuer: 'Org1MSP',
        revoked: false,
        network: 'fabric'
      },
    });

    // Should show results
    await waitFor(() => {
      expect(screen.getByText(/test.pdf/i)).toBeInTheDocument();
    });
  });

  it('displays network-specific information', async () => {
    // Test Fabric network display
    render(<VerifyDocument network="fabric" />);

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    fireEvent.click(hashTabButton);
    fireEvent.change(hashInput, {
      target: { value: '0xtest123' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(screen.getByText(/hyperledger fabric/i)).toBeInTheDocument();
      expect(screen.getByText(/org1msp/i)).toBeInTheDocument();
    });

    // Test Ethereum network display
    jest.clearAllMocks();
    mockedAxios.get = jest.fn().mockResolvedValue({
      data: {
        docHash: '0xtest123',
        fileName: 'eth-test.pdf',
        aiScore: 8,
        isAuthentic: true,
        createdAt: '2026-03-25T10:00:00Z',
        network: 'ethereum'
      },
    });

    const { rerender } = render(<VerifyDocument network="ethereum" />);
    rerender(<VerifyDocument network="ethereum" />);

    fireEvent.click(screen.getByText(/paste hash/i));
    fireEvent.change(screen.getByPlaceholderText(/enter document hash/i), {
      target: { value: '0xtest123' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(screen.getByText(/ethereum sepolia/i)).toBeInTheDocument();
    });
  });

  it('validates hash format before lookup', async () => {
    render(<VerifyDocument network="fabric" />);

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    fireEvent.click(hashTabButton);

    // Test invalid hash format
    fireEvent.change(hashInput, {
      target: { value: 'invalid-hash' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(screen.getByText(/invalid hash format/i)).toBeInTheDocument();
    });

    // API should not be called for invalid hash
    expect(mockedAxios.get).not.toHaveBeenCalled();
  });

  it('displays IPFS information when available', async () => {
    render(<VerifyDocument network="fabric" />);

    mockedAxios.get = jest.fn().mockResolvedValue({
      data: {
        docHash: '0xtest123',
        fileName: 'ipfs-doc.pdf',
        aiScore: 3,
        isAuthentic: true,
        issuer: 'Org1MSP',
        timestamp: '2026-03-25T10:00:00Z',
        revoked: false,
        ipfsCid: 'QmTestIPFSHash123456789',
        network: 'fabric'
      },
    });

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    fireEvent.click(hashTabButton);
    fireEvent.change(hashInput, {
      target: { value: '0xtest123' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(screen.getByText(/QmTestIPFSHash/)).toBeInTheDocument();
      expect(screen.getByText(/ipfs/i)).toBeInTheDocument();
    });
  });

  it('handles network API errors gracefully', async () => {
    render(<VerifyDocument network="fabric" />);

    mockedAxios.get = jest.fn().mockRejectedValue({
      response: {
        status: 500,
        data: { error: 'Gateway connection failed' }
      },
    });

    const hashInput = screen.getByPlaceholderText(/enter document hash/i);
    const hashTabButton = screen.getByText(/paste hash/i);

    fireEvent.click(hashTabButton);
    fireEvent.change(hashInput, {
      target: { value: '0xtest123' }
    });
    fireEvent.click(screen.getByRole('button', { name: /look up/i }));

    await waitFor(() => {
      expect(screen.getByText(/gateway connection failed/i)).toBeInTheDocument();
    });
  });
});