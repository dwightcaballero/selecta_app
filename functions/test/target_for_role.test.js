const test = require("node:test");
const assert = require("node:assert");
const { targetForRole } = require("../lib/index.js");

test("targetForRole maps roles to expected targets", () => {
  // Dealer / Admin -> dealers
  assert.deepStrictEqual(targetForRole("Dealer"), { topic: "dealers" });
  assert.deepStrictEqual(targetForRole("dealer"), { topic: "dealers" });
  assert.deepStrictEqual(targetForRole("Admin"), { topic: "dealers" });
  assert.deepStrictEqual(targetForRole("admin"), { topic: "dealers" });

  // Salesman -> salesmen
  assert.deepStrictEqual(targetForRole("Salesman"), { topic: "salesmen" });
  assert.deepStrictEqual(targetForRole("salesman"), { topic: "salesmen" });

  // Staff -> condition
  assert.deepStrictEqual(targetForRole("Staff"), {
    condition: "'dealers' in topics || 'salesmen' in topics",
  });
  assert.deepStrictEqual(targetForRole("staff"), {
    condition: "'dealers' in topics || 'salesmen' in topics",
  });

  // Store user
  assert.deepStrictEqual(targetForRole("store_hapi101"), {
    topic: "store_hapi101",
  });
  assert.deepStrictEqual(targetForRole("store_abc-123_xyz"), {
    topic: "store_abc-123_xyz",
  });

  // Edge cases
  assert.strictEqual(targetForRole("store_"), undefined); // length <= 6
  assert.strictEqual(targetForRole("unknown_role"), undefined);
  assert.strictEqual(targetForRole(null), undefined);
  assert.strictEqual(targetForRole(undefined), undefined);
  assert.strictEqual(targetForRole(123), undefined);
});
