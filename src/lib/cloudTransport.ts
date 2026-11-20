export interface CloudUser {
  uid: string;
  isAnonymous: boolean;
  getIdToken(): Promise<string>;
}
export function createCloudTransport(deps: {
  enabled: () => boolean;
  user: () => CloudUser | null;
  scope: () => string | null;
  fetch: typeof fetch;
}) {
  const requireConsent = () => {
    if (!deps.enabled())
      throw new Error(
        'Cloud Gemini is off. Enable it in Settings to send messages or audio.',
      );
    if (!deps.user() || deps.user()!.isAnonymous)
      throw new Error('Sign in with Google before using Cloud Gemini.');
  };
  const headers = async () => {
    requireConsent();
    const user = deps.user()!;
    const token = await user.getIdToken();
    requireConsent();
    if (deps.user()?.uid !== user.uid || deps.scope() !== user.uid)
      throw new Error('Account changed. Try again.');
    return {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      'X-Cloud-Consent': 'true',
    };
  };
  const request = async (input: string, init: RequestInit) => {
    const uid = deps.user()?.uid;
    const authHeaders = await headers();
    const response = await deps.fetch(input, { ...init, headers: authHeaders });
    requireConsent();
    if (deps.user()?.uid !== uid)
      throw new Error('Account changed. Response discarded.');
    return response;
  };
  return { requireConsent, headers, request };
}
