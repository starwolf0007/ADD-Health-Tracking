import type { RequestHandler } from 'express';
import { rateLimit } from 'express-rate-limit';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

export async function verifyCloudUser(token: string): Promise<string> {
  if (!process.env.FIREBASE_PROJECT_ID)
    throw new Error('Firebase project is not configured');
  const app =
    getApps().find((item) => item.name === 'neuroflow-server') ??
    initializeApp(
      { projectId: process.env.FIREBASE_PROJECT_ID },
      'neuroflow-server',
    );
  const decoded = await getAuth(app).verifyIdToken(token);
  if (decoded.firebase.sign_in_provider === 'anonymous')
    throw new Error('Google sign-in required');
  const allowed = (process.env.CLOUD_ALLOWED_UIDS || '')
    .split(',')
    .filter(Boolean);
  if (!allowed.includes(decoded.uid)) throw new Error('Account is not allowed');
  return decoded.uid;
}

export function cloudAccess(verify = verifyCloudUser): RequestHandler {
  return async (req, res, next) => {
    if (
      !process.env.GEMINI_API_KEY ||
      !process.env.FIREBASE_PROJECT_ID ||
      !process.env.CLOUD_ALLOWED_UIDS
    ) {
      res
        .status(503)
        .json({ error: 'Cloud AI is not configured for this server.' });
      return;
    }
    if (req.headers['x-cloud-consent'] !== 'true') {
      res.status(403).json({
        error: 'Enable Cloud Gemini in Settings before sending content.',
      });
      return;
    }
    const token = req.headers.authorization?.match(/^Bearer (\S+)$/)?.[1];
    if (!token) {
      res.status(401).json({ error: 'Google sign-in required.' });
      return;
    }
    try {
      res.locals.uid = await verify(token);
      next();
    } catch {
      res
        .status(401)
        .json({ error: 'Sign-in is invalid or this account is not allowed.' });
    }
  };
}
// In-memory limits are for a single Node process; shared hosting needs a shared store.
export const cloudRateLimit = rateLimit({
  windowMs: 60_000,
  limit: 20,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  keyGenerator: (_req, res) => res.locals.uid,
  message: { error: 'Too many AI requests. Try again in a minute.' },
});
export const preAuthRateLimit = rateLimit({
  windowMs: 60_000,
  limit: 60,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
});
