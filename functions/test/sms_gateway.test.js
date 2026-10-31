const test = require("node:test");
const assert = require("node:assert");
const { normalizePhoneNumber, formatAuthHeader } = require("../lib/index.js");

test("normalizePhoneNumber converts Philippine numbers to standard +639 format", () => {
  // Standard 09XX numbers
  assert.strictEqual(normalizePhoneNumber("09171234567"), "+639171234567");
  assert.strictEqual(normalizePhoneNumber("0928 123 4567"), "+639171234567".replace("17", "28"));

  // 10-digit without leading zero
  assert.strictEqual(normalizePhoneNumber("9171234567"), "+639171234567");

  // 12-digit with 639
  assert.strictEqual(normalizePhoneNumber("639171234567"), "+639171234567");

  // Already prefixed with +63
  assert.strictEqual(normalizePhoneNumber("+639171234567"), "+639171234567");

  // Phone number with hyphens and spaces
  assert.strictEqual(normalizePhoneNumber("+63 917-123-4567"), "+639171234567");
});

test("formatAuthHeader formats basic, bearer, or user:password credentials", () => {
  assert.strictEqual(formatAuthHeader(""), undefined);
  assert.strictEqual(formatAuthHeader("Bearer custom_token_123"), "Bearer custom_token_123");
  assert.strictEqual(formatAuthHeader("Basic dXNlcjpwYXNz"), "Basic dXNlcjpwYXNz");

  // user:password gets converted to Basic Base64
  const basicResult = formatAuthHeader("selecta_user:secret123");
  assert.strictEqual(basicResult, `Basic ${Buffer.from("selecta_user:secret123").toString("base64")}`);

  // Raw token without prefix defaults to Bearer
  assert.strictEqual(formatAuthHeader("random_hex_token"), "Bearer random_hex_token");
});
