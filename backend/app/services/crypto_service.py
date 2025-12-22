"""
Token encryption service using Fernet symmetric encryption.

Encrypts OAuth access_token and refresh_token at rest in the database.
Uses SESSION_SECRET as the encryption key (hashed to 32 bytes for Fernet).
"""
import os
import base64
import hashlib
from typing import Optional
from cryptography.fernet import Fernet, InvalidToken
import logging

logger = logging.getLogger(__name__)

# Derive Fernet key from SESSION_SECRET (must be 32 url-safe base64 bytes)
_fernet: Optional[Fernet] = None


def _get_fernet() -> Fernet:
    """Get or create Fernet instance using SESSION_SECRET."""
    global _fernet
    if _fernet is None:
        secret = os.getenv("SESSION_SECRET", "")
        if not secret:
            raise ValueError("SESSION_SECRET environment variable required for token encryption")

        # Hash the secret to get exactly 32 bytes, then base64 encode for Fernet
        key_bytes = hashlib.sha256(secret.encode()).digest()
        key_b64 = base64.urlsafe_b64encode(key_bytes)
        _fernet = Fernet(key_b64)

    return _fernet


def encrypt_token(plaintext: Optional[str]) -> Optional[str]:
    """
    Encrypt a token for storage.

    Returns base64-encoded ciphertext, or None if input is None/empty.
    """
    if not plaintext:
        return None

    try:
        fernet = _get_fernet()
        encrypted = fernet.encrypt(plaintext.encode())
        return encrypted.decode()  # Return as string for DB storage
    except Exception as e:
        logger.error(f"Token encryption failed: {e}")
        raise


def decrypt_token(ciphertext: Optional[str]) -> Optional[str]:
    """
    Decrypt a stored token.

    Returns plaintext, or None if input is None/empty.
    Handles legacy unencrypted tokens gracefully.
    """
    if not ciphertext:
        return None

    try:
        fernet = _get_fernet()
        decrypted = fernet.decrypt(ciphertext.encode())
        return decrypted.decode()
    except InvalidToken:
        # Likely a legacy unencrypted token - return as-is
        # This allows gradual migration without breaking existing sessions
        logger.debug("Token appears unencrypted (legacy), returning as-is")
        return ciphertext
    except Exception as e:
        logger.error(f"Token decryption failed: {e}")
        return None


def is_encrypted(value: Optional[str]) -> bool:
    """Check if a value appears to be Fernet-encrypted."""
    if not value:
        return False

    # Fernet tokens start with 'gAAAAA' (base64 of version byte + timestamp)
    return value.startswith("gAAAAA")
