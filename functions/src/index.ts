import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();

const SYNTHETIC_EMAIL_DOMAIN = "store.selecta.invalid";
const USERNAME_REGEX = /^[a-z0-9._-]{4,20}$/;

// Cloud Functions Configuration: explicit asia-east1 region & resource limits (Phase 0, 1.3)
const regionalFunctions = functions.region("asia-east1");
const FUNCTION_OPTS: functions.RuntimeOptions = {
  maxInstances: 5,
  timeoutSeconds: 30,
  memory: "256MB",
};

/**
 * Staff profiles are not always stored under their auth uid (the app adds them
 * with auto-generated ids), so fall back to a lookup by the token's email.
 */
async function getCallerProfile(context: functions.https.CallableContext) {
  const uid = context.auth?.uid;
  if (!uid) return undefined;

  const byUid = await db.collection("users").doc(uid).get();
  if (byUid.exists) return byUid.data();

  const email = context.auth?.token.email;
  if (!email) return undefined;
  const byEmail = await db.collection("users").where("email", "==", email).limit(1).get();
  return byEmail.empty ? undefined : byEmail.docs[0].data();
}

/**
 * 1. createStoreAccount
 * Callable Cloud Function: Dealer or Admin provisions credentials for a Hapi Store.
 * Sets custom user claims for role and storeId (Phase 5).
 */
export const createStoreAccount = regionalFunctions
  .runWith(FUNCTION_OPTS)
  .https.onCall(async (data, context) => {
    // Authentication check
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated to create a store account."
      );
    }

    // Caller role verification
    const callerData = await getCallerProfile(context);
    const callerRole = callerData?.role || context.auth.token.role;

    if (callerRole !== "Dealer" && callerRole !== "Super Admin" && callerRole !== "Admin") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Dealers and Admins can provision store accounts."
      );
    }

    const { storeId, storeName, dealerName, username, tempPassword } = data;

    if (!storeId || !storeName || !username || !tempPassword) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required fields: storeId, storeName, username, tempPassword."
      );
    }

    const cleanUsername = String(username).toLowerCase().trim();

    // Validate username format: 4-20 chars, lowercase letters, numbers, dot, underscore, hyphen
    if (!USERNAME_REGEX.test(cleanUsername)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Username must be 4-20 characters long and contain only lowercase letters, numbers, '.', '_', or '-'."
      );
    }

    if (String(tempPassword).length < 6) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Temporary password must be at least 6 characters long."
      );
    }

    // Check username uniqueness in store_usernames
    const usernameDoc = await db.collection("store_usernames").doc(cleanUsername).get();
    if (usernameDoc.exists) {
      throw new functions.https.HttpsError(
        "already-exists",
        `The username "${cleanUsername}" is already taken. Please choose another.`
      );
    }

    const syntheticEmail = `${cleanUsername}@${SYNTHETIC_EMAIL_DOMAIN}`;

    try {
      // Create Firebase Auth user
      const userRecord = await auth.createUser({
        email: syntheticEmail,
        password: tempPassword,
        displayName: storeName,
      });

      const uid = userRecord.uid;

      // Set custom claims for store user (Phase 5)
      await auth.setCustomUserClaims(uid, {
        role: "Hapi Store",
        storeId: storeId,
      });

      const now = admin.firestore.FieldValue.serverTimestamp();
      const batch = db.batch();

      // 1. Reserve username mapping
      batch.set(db.collection("store_usernames").doc(cleanUsername), {
        uid: uid,
        storeId: storeId,
        createdAt: now,
      });

      // 2. Create users profile doc
      batch.set(db.collection("users").doc(uid), {
        username: cleanUsername,
        role: "Hapi Store",
        email: syntheticEmail,
        dealerName: dealerName || callerData?.dealerName || "Selecta Dealer",
        dailyRate: 0.0,
        storeId: storeId,
        storeName: storeName,
        mustChangePassword: true,
        createdAt: now,
        updatedAt: now,
      });

      // 3. Link HapiStore doc
      batch.update(db.collection("hapistores").doc(storeId), {
        storeUserUid: uid,
        username: cleanUsername,
        orderingEnabled: true,
        updatedAt: now,
      });

      await batch.commit();

      return {
        success: true,
        uid: uid,
        username: cleanUsername,
        message: `Account created successfully for @${cleanUsername}.`,
      };
    } catch (error: any) {
      throw new functions.https.HttpsError(
        "internal",
        error?.message || "Failed to create store account."
      );
    }
  });

/**
 * 2. storeLogin
 * Verifies credentials, enforces 5-attempt/15-minute lockout and orderingEnabled flag.
 * Adds expireAt (30-day TTL) for transient lockout records (Phase 1.1, Phase 2.5).
 */
export const storeLogin = regionalFunctions
  .runWith(FUNCTION_OPTS)
  .https.onCall(async (data, _context) => {
    const { username, password } = data;

    if (!username || !password) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Username and password are required."
      );
    }

    const cleanUsername = String(username).toLowerCase().trim();

    // 1. Check lockout status
    const attemptDocRef = db.collection("store_login_attempts").doc(cleanUsername);
    const attemptDoc = await attemptDocRef.get();
    const nowMs = Date.now();
    const LOCKOUT_DURATION_MS = 15 * 60 * 1000; // 15 minutes
    const MAX_ATTEMPTS = 5;
    const TTL_30_DAYS = admin.firestore.Timestamp.fromDate(
      new Date(nowMs + 30 * 24 * 60 * 60 * 1000)
    );

    if (attemptDoc.exists) {
      const attemptData = attemptDoc.data();
      const count = attemptData?.count || 0;
      const lastAttemptMs = attemptData?.lastAttempt?.toMillis() || 0;

      if (count >= MAX_ATTEMPTS && nowMs - lastAttemptMs < LOCKOUT_DURATION_MS) {
        const remainingMinutes = Math.ceil(
          (LOCKOUT_DURATION_MS - (nowMs - lastAttemptMs)) / (60 * 1000)
        );
        throw new functions.https.HttpsError(
          "resource-exhausted",
          `Too many failed login attempts. Account is locked. Please try again in ${remainingMinutes} minute(s).`
        );
      }
    }

    // 2. Resolve username to UID
    const usernameDoc = await db.collection("store_usernames").doc(cleanUsername).get();
    if (!usernameDoc.exists) {
      // Record failed attempt
      await attemptDocRef.set(
        {
          count: admin.firestore.FieldValue.increment(1),
          lastAttempt: admin.firestore.FieldValue.serverTimestamp(),
          expireAt: TTL_30_DAYS,
        },
        { merge: true }
      );

      throw new functions.https.HttpsError("not-found", "Invalid username or password.");
    }

    const { uid, storeId } = usernameDoc.data()!;

    // 3. Check if ordering is enabled for this store
    const storeDoc = await db.collection("hapistores").doc(storeId).get();
    if (storeDoc.exists && storeDoc.data()?.orderingEnabled === false) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Online ordering is currently disabled for this store. Please contact your dealer."
      );
    }

    // 4. Verify password against Firebase Auth Identity Toolkit REST API
    const syntheticEmail = `${cleanUsername}@${SYNTHETIC_EMAIL_DOMAIN}`;
    const apiKey = process.env.FIREBASE_WEB_API_KEY || "AIzaSyBANsl70LvRJ4jTemR-O9nUK1yBM7HIoSg";

    try {
      const authResp = await fetch(
        `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            email: syntheticEmail,
            password: password,
            returnSecureToken: true,
          }),
        }
      );

      if (!authResp.ok) {
        // Password invalid: increment failed attempt
        await attemptDocRef.set(
          {
            count: admin.firestore.FieldValue.increment(1),
            lastAttempt: admin.firestore.FieldValue.serverTimestamp(),
            expireAt: TTL_30_DAYS,
          },
          { merge: true }
        );

        throw new functions.https.HttpsError("unauthenticated", "Invalid username or password.");
      }
    } catch (err: any) {
      if (err instanceof functions.https.HttpsError) throw err;
      // Network or API failure fallback: throw internal
      throw new functions.https.HttpsError("internal", "Authentication verification failed.");
    }

    // 5. Successful password verification: Generate custom auth token for client sign-in
    try {
      const customToken = await auth.createCustomToken(uid);

      // Reset failed attempts on success
      await attemptDocRef.delete();

      // Fetch user profile
      const userDoc = await db.collection("users").doc(uid).get();
      const userData = userDoc.data() || {};

      return {
        success: true,
        customToken: customToken,
        mustChangePassword: userData.mustChangePassword === true,
        userProfile: {
          uid: uid,
          username: cleanUsername,
          storeId: storeId,
          storeName: userData.storeName || "",
          dealerName: userData.dealerName || "",
        },
      };
    } catch (error: any) {
      throw new functions.https.HttpsError(
        "internal",
        error?.message || "Login authentication failed."
      );
    }
  });

/**
 * 3. storeChangePassword
 * Updates password and clears mustChangePassword flag.
 */
export const storeChangePassword = regionalFunctions
  .runWith(FUNCTION_OPTS)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated to change password."
      );
    }

    const { newPassword } = data;

    if (!newPassword || String(newPassword).length < 6) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "New password must be at least 6 characters long."
      );
    }

    const uid = context.auth.uid;

    try {
      await auth.updateUser(uid, { password: newPassword });

      await db.collection("users").doc(uid).update({
        mustChangePassword: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        message: "Password changed successfully.",
      };
    } catch (error: any) {
      throw new functions.https.HttpsError(
        "internal",
        error?.message || "Failed to update password."
      );
    }
  });

/**
 * 4. resetStorePassword
 * Dealer or Admin resets store user's password and sets mustChangePassword to true.
 */
export const resetStorePassword = regionalFunctions
  .runWith(FUNCTION_OPTS)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated to reset store password."
      );
    }

    const callerData = await getCallerProfile(context);
    const callerRole = callerData?.role || context.auth.token.role;

    if (callerRole !== "Dealer" && callerRole !== "Super Admin" && callerRole !== "Admin") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Dealers and Admins can reset store passwords."
      );
    }

    const { storeUserUid, newTempPassword } = data;

    if (!storeUserUid || !newTempPassword || String(newTempPassword).length < 6) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Valid storeUserUid and temporary password (min 6 chars) are required."
      );
    }

    try {
      await auth.updateUser(storeUserUid, { password: newTempPassword });

      await db.collection("users").doc(storeUserUid).update({
        mustChangePassword: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        message: "Store password has been reset successfully.",
      };
    } catch (error: any) {
      throw new functions.https.HttpsError(
        "internal",
        error?.message || "Failed to reset store password."
      );
    }
  });

/**
 * 5. getStoreCatalog
 * Returns active catalog products with available/out-of-stock badge.
 * CRITICAL RULE: NEVER returns numeric inventory stock counts or dealer cost prices to stores.
 */
export const getStoreCatalog = regionalFunctions
  .runWith(FUNCTION_OPTS)
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated to view catalog."
      );
    }

    try {
      const productsSnapshot = await db.collection("selecta_products").get();

      const catalog = productsSnapshot.docs.map((doc) => {
        const p = doc.data();
        const stock = typeof p.stock === "number" ? p.stock : 0;
        const isOutOfStock = stock <= 0 || p.outOfStock === true;

        // Filter out dealer cost, margins, and numeric stock counts
        return {
          id: doc.id,
          productName: p.productName || "",
          category: p.category || "",
          sellingPrice: p.sellingPrice || 0.0,
          casePrice: p.casePrice || null,
          piecesPerCase: p.piecesPerCase || null,
          imageUrl: p.imageUrl || "",
          flavor: p.flavorName || p.flavor || "",
          isAvailable: !isOutOfStock, // Only boolean availability badge
        };
      });

      return {
        products: catalog,
      };
    } catch (error: any) {
      throw new functions.https.HttpsError(
        "internal",
        error?.message || "Failed to fetch catalog."
      );
    }
  });

/**
 * 6. setUserClaims (Phase 5)
 * Sets custom user claims for role and storeId to eliminate Firestore rule get() reads.
 */
export const setUserClaims = regionalFunctions
  .runWith(FUNCTION_OPTS)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated to set user claims."
      );
    }

    const callerData = await getCallerProfile(context);
    const callerRole = callerData?.role || context.auth.token.role;

    if (callerRole !== "Super Admin" && callerRole !== "Admin") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Admins can set custom user claims."
      );
    }

    const { targetUid, role, storeId } = data;
    if (!targetUid || !role) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "targetUid and role are required fields."
      );
    }

    const claims: Record<string, any> = { role };
    if (storeId) {
      claims.storeId = storeId;
    }

    try {
      await auth.setCustomUserClaims(targetUid, claims);
      return {
        success: true,
        message: `Custom claims set for UID ${targetUid}`,
      };
    } catch (error: any) {
      throw new functions.https.HttpsError(
        "internal",
        error?.message || "Failed to set custom claims."
      );
    }
  });

/**
 * 7. migrateAllUserClaims (Phase 5)
 * One-off or maintenance callable function to backfill custom claims for existing users.
 */
export const migrateAllUserClaims = regionalFunctions
  .runWith(FUNCTION_OPTS)
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated to migrate claims."
      );
    }

    const callerData = await getCallerProfile(context);
    const callerRole = callerData?.role || context.auth.token.role;

    if (callerRole !== "Super Admin" && callerRole !== "Admin") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Admins can execute claims migration."
      );
    }

    try {
      const usersSnap = await db.collection("users").get();
      let migrated = 0;

      for (const doc of usersSnap.docs) {
        const u = doc.data();
        const uid = doc.id;
        const role = u.role;
        const storeId = u.storeId;

        if (role) {
          const claims: Record<string, any> = { role };
          if (storeId) claims.storeId = storeId;
          try {
            await auth.setCustomUserClaims(uid, claims);
            migrated++;
          } catch (_) {}
        }
      }

      return {
        success: true,
        migratedCount: migrated,
      };
    } catch (error: any) {
      throw new functions.https.HttpsError(
        "internal",
        error?.message || "Migration failed."
      );
    }
  });

/**
 * 8. sendQueuedNotification
 * Firestore trigger: when the app queues a doc in `notifications`, deliver
 * it as an FCM topic message. onCreate ONLY so the status stamp below can
 * never retrigger this function.
 */
const ROLE_TOPICS: Record<string, string> = {
  dealer: "dealers",
  admin: "dealers",
  salesman: "salesmen",
};

export type Target = { topic: string } | { condition: string };

export function targetForRole(role: unknown): Target | undefined {
  if (typeof role !== "string") return undefined;
  const normalized = role.trim();
  if (normalized.toLowerCase() === "staff") {
    return { condition: "'dealers' in topics || 'salesmen' in topics" };
  }
  if (normalized.startsWith("store_")) {
    const topic = normalized.replace(/[^a-zA-Z0-9-_.~%]/g, "_");
    return topic.length > 6 ? { topic } : undefined;
  }
  const topic = ROLE_TOPICS[normalized.toLowerCase()];
  return topic ? { topic } : undefined;
}

export const sendQueuedNotification = regionalFunctions
  .runWith(FUNCTION_OPTS)
  .firestore.document("notifications/{notificationId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();

    // push:false = in-app list only (no system notification). See
    // Appendix A for which events should be push vs in-app only.
    if (data.push === false) {
      await snap.ref.update({
        status: "stored",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const target = targetForRole(data.role);

    if (!target) {
      await snap.ref.update({
        status: "skipped",
        error: "Unknown role",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    // FCM data payload values must all be strings.
    const payloadData: Record<string, string> = {};
    const rawData = (data.data ?? {}) as Record<string, unknown>;
    for (const [key, value] of Object.entries(rawData)) {
      if (value !== null && value !== undefined) {
        payloadData[key] = String(value);
      }
    }
    payloadData.notificationId = context.params.notificationId;

    try {
      await admin.messaging().send({
        ...target,
        notification: {
          title: String(data.title ?? "Selecta Ops").slice(0, 100),
          body: String(data.body ?? "").slice(0, 300),
        },
        data: payloadData,
        android: {
          priority: "high",
          notification: {
            channelId: "selecta_ops_high_importance",
            // Same tag replaces the previous notification instead of
            // stacking (e.g. repeated updates for the same order).
            ...(payloadData.tag ? { tag: payloadData.tag } : {}),
          },
        },
      });
      await snap.ref.update({
        status: "sent",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error: any) {
      functions.logger.error("FCM send failed", {
        role: data.role,
        error: error?.message,
      });
      await snap.ref.update({
        status: "failed",
        error: String(error?.message ?? error).slice(0, 300),
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

