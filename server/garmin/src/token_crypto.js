import crypto from "node:crypto";

const algorithm = "aes-256-gcm";
const keyBytes = 32;
const ivBytes = 12;

export function parseEncryptionKey(value) {
  const raw = String(value || "").trim();
  if (/^[0-9a-f]{64}$/i.test(raw)) {
    return Buffer.from(raw, "hex");
  }
  try {
    const decoded = Buffer.from(raw, "base64");
    return decoded.length === keyBytes ? decoded : null;
  } catch (_) {
    return null;
  }
}

export function requireEncryptionKey(value) {
  const key = parseEncryptionKey(value);
  if (!key || key.length !== keyBytes) {
    throw new Error(
      "INTEGRATION_TOKEN_ENCRYPTION_KEY must be a 32-byte base64 value or 64-character hex value",
    );
  }
  return key;
}

export function encryptJson(value, key) {
  const iv = crypto.randomBytes(ivBytes);
  const cipher = crypto.createCipheriv(algorithm, key, iv);
  const plaintext = Buffer.from(JSON.stringify(value), "utf8");
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return {
    version: 1,
    iv: iv.toString("base64url"),
    tag: cipher.getAuthTag().toString("base64url"),
    ciphertext: ciphertext.toString("base64url"),
  };
}

export function decryptJson(payload, key) {
  if (!payload || payload.version !== 1) {
    throw new Error("unsupported_encrypted_token");
  }
  const iv = Buffer.from(String(payload.iv || ""), "base64url");
  const tag = Buffer.from(String(payload.tag || ""), "base64url");
  const ciphertext = Buffer.from(String(payload.ciphertext || ""), "base64url");
  if (iv.length !== ivBytes || tag.length !== 16 || ciphertext.length === 0) {
    throw new Error("invalid_encrypted_token");
  }
  const decipher = crypto.createDecipheriv(algorithm, key, iv);
  decipher.setAuthTag(tag);
  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  const value = JSON.parse(plaintext.toString("utf8"));
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_decrypted_token");
  }
  return value;
}
