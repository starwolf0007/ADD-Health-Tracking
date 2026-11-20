import { auth } from './firebase';
import { settingsStorage, getStorageUser } from './storage';
import { createCloudTransport } from './cloudTransport';
const transport = createCloudTransport({
  enabled: () => settingsStorage.get().cloudGemini,
  user: () => auth.currentUser,
  scope: getStorageUser,
  fetch: (...args) => fetch(...args),
});
export const requireCloudConsent = transport.requireConsent;
export const cloudFetch = transport.request;
