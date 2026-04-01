import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import axios from 'axios';
import IssueDocument from './IssueDocument';

// Mock axios
jest.mock('axios');
const mockedAxios = axios;

// Mock ethers.js
jest.mock('ethers', () => ({
  ethers: {
    BrowserProvider: jest.fn(),
    Contract: jest.fn(),
    getBytes: jest.fn(),
    keccak256: jest.fn(() => '0xmockedhash'),
  },
}));

describe('IssueDocument', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Default successful API response
    mockedAxios.post = jest.fn().mockResolvedValue({
      data: {
        success: true,
        docHash: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        aiScore: 15,
        aiProvider: 'mock',
        network: 'fabric',
        ipfsCid: 'QmTest123',
      },
    });
  });

  it('renders file input and submit button', () => {
    render(<IssueDocument network="fabric" />);

    expect(screen.getByLabelText(/choose file/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /analyze/i })).toBeInTheDocument();
  });

  it('shows error when no file is selected', async () => {
    render(<IssueDocument network="fabric" />);

    const analyzeButton = screen.getByRole('button', { name: /analyze/i });
    fireEvent.click(analyzeButton);

    await waitFor(() => {
      expect(screen.getByText(/no file selected/i)).toBeInTheDocument();
    });
  });

  it('displays success message after uploading file (Fabric)', async () => {
    render(<IssueDocument network="fabric" />);

    // Create a test file
    const file = new File(['test content'], 'test.png', { type: 'image/png' });
    const fileInput = screen.getByLabelText(/choose file/i);

    // Upload file
    fireEvent.change(fileInput, { target: { files: [file] } });

    // Click analyze
    const analyzeButton = screen.getByRole('button', { name: /analyze/i });
    fireEvent.click(analyzeButton);

    await waitFor(() => {
      expect(screen.getByText(/success/i)).toBeInTheDocument();
      expect(screen.getByText(/0xabcdef/)).toBeInTheDocument();
      expect(screen.getByText(/AI Score: 15/i)).toBeInTheDocument();
    });

    // Verify API call
    expect(mockedAxios.post).toHaveBeenCalledWith(
      'http://localhost:5000/api/fabric/analyze',
      expect.any(FormData)
    );
  });

  it('displays success message after uploading file (Ethereum)', async () => {
    render(<IssueDocument network="ethereum" />);

    mockedAxios.post = jest.fn().mockResolvedValue({
      data: {
        success: true,
        docHash: '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        aiScore: 8,
        aiProvider: 'mock',
        network: 'ethereum',
      },
    });

    const file = new File(['test content'], 'test.txt', { type: 'text/plain' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [file] } });

    const analyzeButton = screen.getByRole('button', { name: /analyze/i });
    fireEvent.click(analyzeButton);

    await waitFor(() => {
      expect(screen.getByText(/success/i)).toBeInTheDocument();
      expect(screen.getByText(/0x123456/)).toBeInTheDocument();
    });

    expect(mockedAxios.post).toHaveBeenCalledWith(
      'http://localhost:5000/api/analyze',
      expect.any(FormData)
    );
  });

  it('handles API errors gracefully', async () => {
    render(<IssueDocument network="fabric" />);

    // Mock API failure
    mockedAxios.post = jest.fn().mockRejectedValue({
      response: {
        status: 400,
        data: { error: 'AI check failed: content appears synthetic' },
      },
    });

    const file = new File(['suspicious content'], 'fake.jpg', { type: 'image/jpeg' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [file] } });

    const analyzeButton = screen.getByRole('button', { name: /analyze/i });
    fireEvent.click(analyzeButton);

    await waitFor(() => {
      expect(screen.getByText(/AI check failed/i)).toBeInTheDocument();
    });
  });

  it('shows loading state during upload', async () => {
    render(<IssueDocument network="fabric" />);

    // Mock delayed API response
    let resolveApiCall;
    mockedAxios.post = jest.fn().mockReturnValue(
      new Promise((resolve) => {
        resolveApiCall = resolve;
      })
    );

    const file = new File(['test content'], 'test.png', { type: 'image/png' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /analyze/i }));

    // Should show loading state
    await waitFor(() => {
      expect(screen.getByText(/analyzing/i)).toBeInTheDocument();
    });

    // Resolve the API call
    resolveApiCall({
      data: {
        success: true,
        docHash: '0xtest',
        aiScore: 10,
        network: 'fabric',
      },
    });

    // Should show success
    await waitFor(() => {
      expect(screen.getByText(/success/i)).toBeInTheDocument();
    });
  });

  it('switches API endpoint based on network', () => {
    // Test Fabric network
    const { rerender } = render(<IssueDocument network="fabric" />);

    const file = new File(['test'], 'test.txt', { type: 'text/plain' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /analyze/i }));

    expect(mockedAxios.post).toHaveBeenCalledWith(
      'http://localhost:5000/api/fabric/analyze',
      expect.any(FormData)
    );

    // Clear mocks and test Ethereum network
    jest.clearAllMocks();
    rerender(<IssueDocument network="ethereum" />);

    fireEvent.change(fileInput, { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /analyze/i }));

    expect(mockedAxios.post).toHaveBeenCalledWith(
      'http://localhost:5000/api/analyze',
      expect.any(FormData)
    );
  });

  it('displays IPFS CID when available', async () => {
    render(<IssueDocument network="fabric" />);

    mockedAxios.post = jest.fn().mockResolvedValue({
      data: {
        success: true,
        docHash: '0xtest',
        aiScore: 5,
        network: 'fabric',
        ipfsCid: 'QmTestIPFSHash123456789',
      },
    });

    const file = new File(['test content'], 'test.pdf', { type: 'application/pdf' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /analyze/i }));

    await waitFor(() => {
      expect(screen.getByText(/QmTestIPFSHash/)).toBeInTheDocument();
    });
  });

  it('handles large files within limit', async () => {
    render(<IssueDocument network="fabric" />);

    // Create a 5MB file (within 10MB limit)
    const largeContent = 'x'.repeat(5 * 1024 * 1024);
    const largeFile = new File([largeContent], 'large.txt', { type: 'text/plain' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [largeFile] } });
    fireEvent.click(screen.getByRole('button', { name: /analyze/i }));

    await waitFor(() => {
      expect(mockedAxios.post).toHaveBeenCalled();
    });
  });

  it('displays network-specific success messages', async () => {
    // Test Fabric success message
    render(<IssueDocument network="fabric" />);

    const file = new File(['test'], 'test.txt', { type: 'text/plain' });
    const fileInput = screen.getByLabelText(/choose file/i);

    fireEvent.change(fileInput, { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /analyze/i }));

    await waitFor(() => {
      expect(screen.getByText(/anchored on Hyperledger Fabric/i)).toBeInTheDocument();
    });

    // Test Ethereum success message
    jest.clearAllMocks();
    mockedAxios.post = jest.fn().mockResolvedValue({
      data: {
        success: true,
        docHash: '0xtest',
        aiScore: 5,
        network: 'ethereum',
      },
    });

    const { rerender } = render(<IssueDocument network="ethereum" />);
    rerender(<IssueDocument network="ethereum" />);

    fireEvent.change(fileInput, { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: /analyze/i }));

    await waitFor(() => {
      expect(screen.getByText(/anchored on Ethereum/i)).toBeInTheDocument();
    });
  });
});