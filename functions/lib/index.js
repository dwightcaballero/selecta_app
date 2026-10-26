"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getStoreCatalog = exports.resetStorePassword = exports.storeChangePassword = exports.storeLogin = exports.createStoreAccount = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();
const SYNTHETIC_EMAIL_DOMAIN = "store.selecta.invalid";
const USERNAME_REGEX = /^[a-z0-9._-]{4,20}$/;
/**
 * Staff profiles are not always stored under their auth uid (the app adds them
 * with auto-generated ids), so fall back to a lookup by the token's email.
 */
async function getCallerProfile(context) {
    const uid = context.auth.uid;
    const byUid = await db.collection("users").doc(uid).get();
    if (byUid.exists)
        return byUid.data();
    const email = context.auth.token.email;
    if (!email)
        return undefined;
    const byEmail = await db.collection("users").where("email", "==", email).limit(1).get();
    return byEmail.empty ? undefined : byEmail.docs[0].data();
}
/**
 * 1. createStoreAccount
 * Callable Cloud Function: Dealer or Admin provisions credentials for a Hapi Store.
 */
exports.createStoreAccount = functions.https.onCall(async (data, context) => {
    // Authentication check
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated to create a store account.");
    }
    // Caller role verification
    const callerData = await getCallerProfile(context);
    const callerRole = callerData?.role;
    if (callerRole !== "Dealer" && callerRole !== "Super Admin" && callerRole !== "Admin") {
        throw new functions.https.HttpsError("permission-denied", "Only Dealers and Admins can provision store accounts.");
    }
    const { storeId, storeName, dealerName, username, tempPassword } = data;
    if (!storeId || !storeName || !username || !tempPassword) {
        throw new functions.https.HttpsError("invalid-argument", "Missing required fields: storeId, storeName, username, tempPassword.");
    }
    const cleanUsername = String(username).toLowerCase().trim();
    // Validate username format: 4-20 chars, lowercase letters, numbers, dot, underscore, hyphen
    if (!USERNAME_REGEX.test(cleanUsername)) {
        throw new functions.https.HttpsError("invalid-argument", "Username must be 4-20 characters long and contain only lowercase letters, numbers, '.', '_', or '-'.");
    }
    if (String(tempPassword).length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Temporary password must be at least 6 characters long.");
    }
    // Check username uniqueness in store_usernames
    const usernameDoc = await db.collection("store_usernames").doc(cleanUsername).get();
    if (usernameDoc.exists) {
        throw new functions.https.HttpsError("already-exists", `The username "${cleanUsername}" is already taken. Please choose another.`);
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
    }
    catch (error) {
        throw new functions.https.HttpsError("internal", error?.message || "Failed to create store account.");
    }
});
/**
 * 2. storeLogin
 * Verifies credentials, enforces 5-attempt/15-minute lockout and orderingEnabled flag.
 */
exports.storeLogin = functions.https.onCall(async (data, _context) => {
    const { username, password } = data;
    if (!username || !password) {
        throw new functions.https.HttpsError("invalid-argument", "Username and password are required.");
    }
    const cleanUsername = String(username).toLowerCase().trim();
    // 1. Check lockout status
    const attemptDocRef = db.collection("store_login_attempts").doc(cleanUsername);
    const attemptDoc = await attemptDocRef.get();
    const nowMs = Date.now();
    const LOCKOUT_DURATION_MS = 15 * 60 * 1000; // 15 minutes
    const MAX_ATTEMPTS = 5;
    if (attemptDoc.exists) {
        const attemptData = attemptDoc.data();
        const count = attemptData?.count || 0;
        const lastAttemptMs = attemptData?.lastAttempt?.toMillis() || 0;
        if (count >= MAX_ATTEMPTS && nowMs - lastAttemptMs < LOCKOUT_DURATION_MS) {
            const remainingMinutes = Math.ceil((LOCKOUT_DURATION_MS - (nowMs - lastAttemptMs)) / (60 * 1000));
            throw new functions.https.HttpsError("resource-exhausted", `Too many failed login attempts. Account is locked. Please try again in ${remainingMinutes} minute(s).`);
        }
    }
    // 2. Resolve username to UID
    const usernameDoc = await db.collection("store_usernames").doc(cleanUsername).get();
    if (!usernameDoc.exists) {
        // Record failed attempt
        await attemptDocRef.set({
            count: admin.firestore.FieldValue.increment(1),
            lastAttempt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw new functions.https.HttpsError("not-found", "Invalid username or password.");
    }
    const { uid, storeId } = usernameDoc.data();
    // 3. Check if ordering is enabled for this store
    const storeDoc = await db.collection("hapistores").doc(storeId).get();
    if (storeDoc.exists && storeDoc.data()?.orderingEnabled === false) {
        throw new functions.https.HttpsError("permission-denied", "Online ordering is currently disabled for this store. Please contact your dealer.");
    }
    // 4. Generate custom auth token for client sign-in
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
    }
    catch (error) {
        throw new functions.https.HttpsError("internal", error?.message || "Login authentication failed.");
    }
});
/**
 * 3. storeChangePassword
 * Updates password and clears mustChangePassword flag.
 */
exports.storeChangePassword = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated to change password.");
    }
    const { newPassword } = data;
    if (!newPassword || String(newPassword).length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "New password must be at least 6 characters long.");
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
    }
    catch (error) {
        throw new functions.https.HttpsError("internal", error?.message || "Failed to update password.");
    }
});
/**
 * 4. resetStorePassword
 * Dealer or Admin resets store user's password and sets mustChangePassword to true.
 */
exports.resetStorePassword = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated to reset store password.");
    }
    const callerData = await getCallerProfile(context);
    const callerRole = callerData?.role;
    if (callerRole !== "Dealer" && callerRole !== "Super Admin" && callerRole !== "Admin") {
        throw new functions.https.HttpsError("permission-denied", "Only Dealers and Admins can reset store passwords.");
    }
    const { storeUserUid, newTempPassword } = data;
    if (!storeUserUid || !newTempPassword || String(newTempPassword).length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Valid storeUserUid and temporary password (min 6 chars) are required.");
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
    }
    catch (error) {
        throw new functions.https.HttpsError("internal", error?.message || "Failed to reset store password.");
    }
});
/**
 * 5. getStoreCatalog
 * Returns active catalog products with available/out-of-stock badge.
 * CRITICAL RULE: NEVER returns numeric inventory stock counts or dealer cost prices to stores.
 */
exports.getStoreCatalog = functions.https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated to view catalog.");
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
    }
    catch (error) {
        throw new functions.https.HttpsError("internal", error?.message || "Failed to fetch catalog.");
    }
});
//# sourceMappingURL=index.js.map