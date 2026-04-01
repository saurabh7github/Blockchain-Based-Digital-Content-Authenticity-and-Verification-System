'use strict';

/**
 * utils/secretsManager.js
 *
 * Unified secrets management for production environments.
 * Supports AWS Secrets Manager in production, .env fallback in development.
 *
 * Usage:
 *   const secrets = new SecretsManager();
 *   const dbPassword = await secrets.get('mongodb_password');
 *   const jwtSecret = await secrets.get('jwt_secret');
 */

const AWS = require('aws-sdk');
require('dotenv').config();

class SecretsManager {
  constructor() {
    this.environment = process.env.NODE_ENV || 'development';
    this.useAWS = this.environment === 'production' && process.env.AWS_REGION;
    this.cache = new Map();
    this.cacheTimeout = 5 * 60 * 1000; // 5 minutes

    if (this.useAWS) {
      this.secretsManager = new AWS.SecretsManager({
        region: process.env.AWS_REGION
      });
    }
  }

  /**
   * Get secret value
   * @param {string} secretName - Secret name (e.g., 'mongodb_password')
   * @returns {Promise<string>} Secret value
   */
  async get(secretName) {
    // Check cache first
    if (this.cache.has(secretName)) {
      const cached = this.cache.get(secretName);
      if (Date.now() - cached.timestamp < this.cacheTimeout) {
        return cached.value;
      }
      this.cache.delete(secretName);
    }

    let value;

    if (this.useAWS) {
      value = await this.getFromAWS(secretName);
    } else {
      // Development: use environment variables from .env file
      value = process.env[secretName.toUpperCase()];
      if (!value) {
        throw new Error(`Secret '${secretName}' not found in environment variables`);
      }
    }

    // Cache the value
    this.cache.set(secretName, {
      value,
      timestamp: Date.now()
    });

    return value;
  }

  /**
   * Get secret from AWS Secrets Manager
   * @private
   */
  async getFromAWS(secretName) {
    try {
      const params = {
        SecretId: `docverifier/production/${secretName}`
      };

      const data = await this.secretsManager.getSecretValue(params).promise();
      return data.SecretString;
    } catch (error) {
      if (error.code === 'ResourceNotFoundException') {
        throw new Error(`Secret 'docverifier/production/${secretName}' not found in AWS Secrets Manager`);
      }
      throw error;
    }
  }

  /**
   * Get multiple secrets at once
   * @param {string[]} secretNames - Array of secret names
   * @returns {Promise<Object>} Object with secret names as keys
   */
  async getMultiple(secretNames) {
    const results = {};
    for (const name of secretNames) {
      results[name] = await this.get(name);
    }
    return results;
  }

  /**
   * Put secret value (for setup/rotation)
   * @param {string} secretName - Secret name
   * @param {string} value - Secret value
   */
  async put(secretName, value) {
    if (!this.useAWS) {
      console.warn('⚠️  Secrets Manager in development mode - cannot store secrets remotely');
      return;
    }

    try {
      const params = {
        Name: `docverifier/production/${secretName}`,
        SecretString: value,
        ClientRequestToken: require('crypto').randomUUID()
      };

      await this.secretsManager.putSecretValue(params).promise();
      console.log(`✅ Secret '${secretName}' stored in AWS Secrets Manager`);

      // Invalidate cache
      this.cache.delete(secretName);
    } catch (error) {
      throw new Error(`Failed to store secret: ${error.message}`);
    }
  }

  /**
   * Rotate secret (simple implementation - implement proper rotation as needed)
   * @param {string} secretName - Secret name
   * @param {string} newValue - New secret value
   */
  async rotate(secretName, newValue) {
    if (!this.useAWS) {
      console.warn('⚠️  Cannot rotate secrets in development mode');
      return;
    }

    try {
      // Store previous value as backup
      const currentValue = await this.get(secretName);
      await this.put(`${secretName}_backup_${Date.now()}`, currentValue);

      // Update with new value
      await this.put(secretName, newValue);
      console.log(`✅ Secret '${secretName}' rotated successfully`);
    } catch (error) {
      throw new Error(`Secret rotation failed: ${error.message}`);
    }
  }

  /**
   * List all secrets (development only)
   */
  listSecrets() {
    if (this.useAWS) {
      console.warn('⚠️  Cannot list AWS Secrets in production. Use AWS Console or CLI.');
      return;
    }

    const secrets = Object.keys(process.env)
      .filter(key => !['NODE_ENV', 'PORT', 'AWS_REGION', 'DEBUG'].includes(key))
      .reduce((acc, key) => {
        acc[key] = process.env[key].substring(0, 10) + '...';
        return acc;
      }, {});

    console.table(secrets);
  }
}

module.exports = SecretsManager;
