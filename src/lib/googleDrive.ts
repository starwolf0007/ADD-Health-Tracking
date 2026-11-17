// Google Drive API service using client-side OAuth Bearer token
// Strictly adheres to the least-privilege `drive.file` scope:
// Only files explicitly created or opened by NeuroFlow are accessed.

export const GOOGLE_DRIVE_FILE_SCOPE = 'https://www.googleapis.com/auth/drive.file' as const;

const FORBIDDEN_BROAD_DRIVE_SCOPES = new Set([
  'https://www.googleapis.com/auth/drive',
  'https://www.googleapis.com/auth/drive.readonly',
  'https://www.googleapis.com/auth/drive.metadata',
  'https://www.googleapis.com/auth/drive.metadata.readonly',
  'https://www.googleapis.com/auth/drive.appdata',
  'https://www.googleapis.com/auth/drive.photos.readonly',
]);

export const NEUROFLOW_APP_PROPERTIES: Record<string, string> = {
  app: 'neuroflow',
  scope: 'drive.file',
  managedBy: 'neuroflow-local-first-backup',
};

/**
 * Verifies that requested OAuth scopes strictly adhere to the least-privilege
 * `drive.file` scope and do not request broader Drive permissions.
 */
export function verifyDriveFileScope(scopes: readonly string[]): boolean {
  let hasDriveFileScope = false;
  for (const rawScope of scopes) {
    const scope = rawScope.trim();
    if (FORBIDDEN_BROAD_DRIVE_SCOPES.has(scope)) {
      console.error(
        `[DriveSync] Security violation: Forbidden broad Google Drive scope detected ("${scope}"). Only "${GOOGLE_DRIVE_FILE_SCOPE}" is permitted.`
      );
      return false;
    }
    if (scope === GOOGLE_DRIVE_FILE_SCOPE) {
      hasDriveFileScope = true;
    }
  }
  return hasDriveFileScope;
}

export interface DriveFile {
  id: string;
  name: string;
  mimeType: string;
  modifiedTime: string;
  size?: string;
  webViewLink?: string;
  iconLink?: string;
  thumbnailLink?: string;
  starred?: boolean;
  appProperties?: Record<string, string>;
}

export type DriveErrorCode =
  | 'TOKEN_EXPIRED'
  | 'NETWORK_ERROR'
  | 'RATE_LIMITED'
  | 'SERVER_ERROR'
  | 'SCOPE_FORBIDDEN'
  | 'NOT_FOUND'
  | 'BAD_REQUEST'
  | 'UNKNOWN_ERROR';

export class DriveSyncError extends Error {
  readonly code: DriveErrorCode;
  readonly status?: number;
  readonly retryable: boolean;
  readonly attempts: number;
  readonly timestamp: string;

  constructor(params: {
    message: string;
    code: DriveErrorCode;
    status?: number;
    retryable: boolean;
    attempts?: number;
  }) {
    super(params.message);
    this.name = 'DriveSyncError';
    this.code = params.code;
    this.status = params.status;
    this.retryable = params.retryable;
    this.attempts = params.attempts ?? 1;
    this.timestamp = new Date().toISOString();
  }
}

export type DriveBackupStatus =
  | 'idle'
  | 'syncing'
  | 'synced'
  | 'error'
  | 'token_expired'
  | 'offline';

export interface DriveBackupHealthState {
  status: DriveBackupStatus;
  lastSyncedAt: string | null;
  lastBackupFileName: string | null;
  lastBackupFileId: string | null;
  syncError: string | null;
  syncErrorCode: DriveErrorCode | null;
  lastErrorAt: string | null;
  retryAttempt: number;
  maxRetries: number;
}

export interface RetryOptions {
  maxRetries?: number;
  baseDelayMs?: number;
  maxDelayMs?: number;
  operationName?: string;
  refreshToken?: () => Promise<string | null>;
  onRetry?: (attempt: number, delayMs: number, error: DriveSyncError) => void;
}

type TokenRefreshHandler = () => Promise<string | null>;
type TokenExpiredHandler = (reason: string) => void;

let registeredTokenRefreshHandler: TokenRefreshHandler | null = null;
let registeredTokenExpiredHandler: TokenExpiredHandler | null = null;

/**
 * Registers auth lifecycle callbacks so the Drive sync module can attempt
 * token refresh or notify the auth context when an OAuth token expires (HTTP 401).
 */
export function registerDriveTokenHandlers(handlers: {
  onRefreshToken?: TokenRefreshHandler | null;
  onTokenExpired?: TokenExpiredHandler | null;
}): void {
  registeredTokenRefreshHandler = handlers.onRefreshToken ?? null;
  registeredTokenExpiredHandler = handlers.onTokenExpired ?? null;
}

// ---------------------------------------------------------------------------
// Least-Privilege File Provenance Registry (drive.file guard)
// ---------------------------------------------------------------------------
const MANAGED_FILES_STORAGE_KEY = 'neuroflow_drive_managed_file_ids';
const inMemoryManagedFileIds = new Set<string>();

function getManagedFileIds(): Set<string> {
  if (typeof window === 'undefined' || !window.localStorage) {
    return new Set<string>(inMemoryManagedFileIds);
  }
  try {
    const raw = localStorage.getItem(MANAGED_FILES_STORAGE_KEY);
    if (!raw) return new Set<string>(inMemoryManagedFileIds);
    const parsed = JSON.parse(raw);
    const combined = new Set<string>(inMemoryManagedFileIds);
    if (Array.isArray(parsed)) {
      parsed.forEach((id) => {
        if (typeof id === 'string') combined.add(id);
      });
    }
    return combined;
  } catch {
    return new Set<string>(inMemoryManagedFileIds);
  }
}

function recordManagedFileIds(ids: string[]): void {
  if (ids.length === 0) return;
  ids.forEach((id) => {
    if (id && id.trim()) inMemoryManagedFileIds.add(id.trim());
  });
  if (typeof window === 'undefined' || !window.localStorage) {
    return;
  }
  try {
    const current = getManagedFileIds();
    localStorage.setItem(MANAGED_FILES_STORAGE_KEY, JSON.stringify(Array.from(current)));
  } catch {
    // Ignore storage quota issues for provenance cache
  }
}

function removeManagedFileId(id: string): void {
  if (!id) return;
  inMemoryManagedFileIds.delete(id);
  if (typeof window === 'undefined' || !window.localStorage) return;
  try {
    const current = getManagedFileIds();
    current.delete(id);
    localStorage.setItem(MANAGED_FILES_STORAGE_KEY, JSON.stringify(Array.from(current)));
  } catch {
    // Ignore
  }
}

export function isAppManagedDriveFile(file: DriveFile | string): boolean {
  const knownIds = getManagedFileIds();
  if (typeof file === 'string') {
    return knownIds.has(file);
  }
  if (knownIds.has(file.id)) return true;
  if (file.appProperties?.app === 'neuroflow') return true;
  if (
    file.name.startsWith('NeuroFlow-Backup-') ||
    file.name.startsWith('NeuroFlow-AutoBackup-')
  ) {
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Backup Health State Management & Persistence
// ---------------------------------------------------------------------------
const BACKUP_HEALTH_STORAGE_KEY = 'neuroflow_drive_backup_health';

let activeDriveScope = 'guest';

export function setDriveBackupScope(scope: string | null | undefined): void {
  activeDriveScope = scope && scope.trim() ? scope.trim() : 'guest';
  currentBackupHealth = loadInitialBackupHealth();
  notifyHealthListeners();
}

function getScopedHealthKey(): string {
  return `${BACKUP_HEALTH_STORAGE_KEY}_${activeDriveScope}`;
}

const DEFAULT_BACKUP_HEALTH: DriveBackupHealthState = {
  status: 'idle',
  lastSyncedAt: null,
  lastBackupFileName: null,
  lastBackupFileId: null,
  syncError: null,
  syncErrorCode: null,
  lastErrorAt: null,
  retryAttempt: 0,
  maxRetries: 3,
};

function loadInitialBackupHealth(): DriveBackupHealthState {
  if (typeof window === 'undefined' || !window.localStorage) {
    return { ...DEFAULT_BACKUP_HEALTH };
  }
  try {
    const raw =
      localStorage.getItem(getScopedHealthKey()) ||
      localStorage.getItem(BACKUP_HEALTH_STORAGE_KEY);
    if (!raw) return { ...DEFAULT_BACKUP_HEALTH };
    const parsed = JSON.parse(raw);
    return {
      ...DEFAULT_BACKUP_HEALTH,
      ...parsed,
      status:
        parsed.status === 'syncing'
          ? parsed.lastSyncedAt
            ? 'synced'
            : 'idle'
          : parsed.status || 'idle',
      retryAttempt: 0,
    };
  } catch {
    return { ...DEFAULT_BACKUP_HEALTH };
  }
}

let currentBackupHealth: DriveBackupHealthState = loadInitialBackupHealth();
export type BackupHealthListener = (state: DriveBackupHealthState) => void;
const healthListeners = new Set<BackupHealthListener>();

function notifyHealthListeners(): void {
  healthListeners.forEach((listener) => {
    try {
      listener({ ...currentBackupHealth });
    } catch (e) {
      console.error('[DriveSync] Health listener error:', e);
    }
  });
}

function updateBackupHealth(
  updates: Partial<DriveBackupHealthState>
): DriveBackupHealthState {
  currentBackupHealth = {
    ...currentBackupHealth,
    ...updates,
  };
  if (typeof window !== 'undefined' && window.localStorage) {
    try {
      const serialized = JSON.stringify(currentBackupHealth);
      localStorage.setItem(getScopedHealthKey(), serialized);
      localStorage.setItem(BACKUP_HEALTH_STORAGE_KEY, serialized);
    } catch (err) {
      console.warn('[DriveSync] Failed to persist backup health state:', err);
    }
  }
  notifyHealthListeners();
  return { ...currentBackupHealth };
}

// ---------------------------------------------------------------------------
// Exponential Backoff & Error Classification Helpers
// ---------------------------------------------------------------------------
export function calculateBackoffDelay(
  attempt: number,
  baseDelayMs = 1000,
  maxDelayMs = 10000,
  retryAfterSeconds?: number
): number {
  if (retryAfterSeconds && Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0) {
    return Math.min(retryAfterSeconds * 1000, maxDelayMs);
  }
  const exponential = baseDelayMs * Math.pow(2, Math.max(0, attempt - 1));
  const jitter = Math.floor(Math.random() * (exponential * 0.25));
  return Math.min(exponential + jitter, maxDelayMs);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function parseErrorResponse(
  response: Response,
  fallbackMessage: string,
  attempts: number
): Promise<DriveSyncError> {
  let apiMessage = '';
  let apiReason = '';
  let apiStatus = '';

  try {
    const text = await response.text();
    if (text) {
      const parsed = JSON.parse(text);
      apiMessage = parsed?.error?.message || '';
      apiStatus = parsed?.error?.status || '';
      const firstError = Array.isArray(parsed?.error?.errors) ? parsed.error.errors[0] : null;
      apiReason = firstError?.reason || '';
    }
  } catch {
    // Response was not JSON; use statusText fallback
  }

  const status = response.status;
  const detail = apiMessage || response.statusText || fallbackMessage;

  if (status === 401 || apiStatus === 'UNAUTHENTICATED' || apiReason === 'authError') {
    return new DriveSyncError({
      message: `Google Drive authorization expired or invalid (HTTP 401). Please reconnect your Google account.`,
      code: 'TOKEN_EXPIRED',
      status: 401,
      retryable: false,
      attempts,
    });
  }

  if (status === 403) {
    const isRateLimit =
      apiReason === 'userRateLimitExceeded' ||
      apiReason === 'rateLimitExceeded' ||
      apiReason === 'quotaExceeded' ||
      detail.toLowerCase().includes('rate limit');

    if (isRateLimit) {
      return new DriveSyncError({
        message: `Google Drive rate limit reached: ${detail}`,
        code: 'RATE_LIMITED',
        status: 403,
        retryable: true,
        attempts,
      });
    }

    return new DriveSyncError({
      message: `Access denied under least-privilege drive.file scope: ${detail}. NeuroFlow only accesses files it explicitly created.`,
      code: 'SCOPE_FORBIDDEN',
      status: 403,
      retryable: false,
      attempts,
    });
  }

  if (status === 404) {
    return new DriveSyncError({
      message: `File not found or not accessible under drive.file scope (HTTP 404).`,
      code: 'NOT_FOUND',
      status: 404,
      retryable: false,
      attempts,
    });
  }

  if (status === 429) {
    return new DriveSyncError({
      message: `Too many requests to Google Drive API (HTTP 429): ${detail}`,
      code: 'RATE_LIMITED',
      status: 429,
      retryable: true,
      attempts,
    });
  }

  if (status === 408 || status >= 500) {
    return new DriveSyncError({
      message: `Google Drive server error (HTTP ${status}): ${detail}`,
      code: 'SERVER_ERROR',
      status,
      retryable: true,
      attempts,
    });
  }

  if (status >= 400 && status < 500) {
    return new DriveSyncError({
      message: detail || fallbackMessage,
      code: 'BAD_REQUEST',
      status,
      retryable: false,
      attempts,
    });
  }

  return new DriveSyncError({
    message: detail || fallbackMessage,
    code: 'UNKNOWN_ERROR',
    status,
    retryable: false,
    attempts,
  });
}

function classifyNetworkFailure(
  err: unknown,
  operationName: string,
  attempts: number
): DriveSyncError {
  if (err instanceof DriveSyncError) {
    return err;
  }
  const rawMessage = err instanceof Error ? err.message : String(err || 'Unknown network error');
  const isOffline = typeof navigator !== 'undefined' && navigator.onLine === false;
  return new DriveSyncError({
    message: isOffline
      ? `Network offline during ${operationName}. Check your internet connection.`
      : `Network connection dropped during ${operationName}: ${rawMessage}`,
    code: 'NETWORK_ERROR',
    retryable: true,
    attempts,
  });
}

/**
 * Executes a Google Drive API request with exponential backoff retry for
 * network drops, rate limits (429/403-rate-limit), and transient 5xx errors,
 * plus automatic token refresh/expiration handling for HTTP 401 responses.
 */
export async function executeDriveRequestWithRetry<T>(
  initialToken: string,
  requestFactory: (activeToken: string) => Promise<Response>,
  responseParser: (response: Response) => Promise<T>,
  options?: RetryOptions & { allow204?: boolean; updateHealthOnSync?: boolean }
): Promise<T> {
  const maxRetries = options?.maxRetries ?? 3;
  const baseDelayMs = options?.baseDelayMs ?? 1000;
  const maxDelayMs = options?.maxDelayMs ?? 10000;
  const operationName = options?.operationName ?? 'Google Drive request';
  const allow204 = options?.allow204 ?? false;
  const updateHealthOnSync = options?.updateHealthOnSync ?? false;

  let activeToken = (initialToken || '').trim();
  if (!activeToken) {
    const tokenErr = new DriveSyncError({
      message:
        'Missing OAuth access token. Please sign in with Google to authorize drive.file access.',
      code: 'TOKEN_EXPIRED',
      status: 401,
      retryable: false,
      attempts: 0,
    });
    console.warn(`[DriveSync] ${operationName} aborted: ${tokenErr.message}`);
    if (updateHealthOnSync) {
      updateBackupHealth({
        status: 'token_expired',
        syncError: tokenErr.message,
        syncErrorCode: tokenErr.code,
        lastErrorAt: tokenErr.timestamp,
        retryAttempt: 0,
      });
    }
    throw tokenErr;
  }

  let hasAttemptedTokenRefresh = false;

  for (let attempt = 1; attempt <= maxRetries + 1; attempt++) {
    try {
      if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        throw new DriveSyncError({
          message: `Device is offline; cannot complete ${operationName}.`,
          code: 'NETWORK_ERROR',
          retryable: true,
          attempts: attempt,
        });
      }

      const response = await requestFactory(activeToken);

      if (response.ok || (allow204 && response.status === 204)) {
        return await responseParser(response);
      }

      const syncError = await parseErrorResponse(
        response,
        `Failed to complete ${operationName}`,
        attempt
      );

      // Handle expired OAuth token (HTTP 401)
      if (syncError.code === 'TOKEN_EXPIRED') {
        console.warn(
          `[DriveSync] OAuth token expired (HTTP 401) during "${operationName}" (attempt ${attempt}).`
        );

        const refreshFn = options?.refreshToken ?? registeredTokenRefreshHandler;
        if (!hasAttemptedTokenRefresh && refreshFn) {
          hasAttemptedTokenRefresh = true;
          console.info(`[DriveSync] Attempting OAuth token refresh for "${operationName}"...`);
          try {
            const refreshedToken = await refreshFn();
            if (refreshedToken && refreshedToken.trim()) {
              activeToken = refreshedToken.trim();
              console.info(
                `[DriveSync] OAuth token refreshed successfully. Retrying "${operationName}"...`
              );
              attempt--; // Do not consume a backoff retry slot for the single token refresh
              continue;
            }
          } catch (refreshErr) {
            console.warn('[DriveSync] OAuth token refresh attempt failed:', refreshErr);
          }
        }

        if (registeredTokenExpiredHandler) {
          try {
            registeredTokenExpiredHandler(syncError.message);
          } catch (handlerErr) {
            console.error('[DriveSync] Token expired handler error:', handlerErr);
          }
        }

        if (updateHealthOnSync) {
          updateBackupHealth({
            status: 'token_expired',
            syncError: syncError.message,
            syncErrorCode: 'TOKEN_EXPIRED',
            lastErrorAt: syncError.timestamp,
            retryAttempt: 0,
          });
        }
        throw syncError;
      }

      // Parse Retry-After header if provided on 429 / 503
      const retryAfterHeader = response.headers?.get?.('Retry-After');
      const retryAfterSeconds = retryAfterHeader ? parseInt(retryAfterHeader, 10) : undefined;

      if (!syncError.retryable || attempt > maxRetries) {
        console.error(
          `[DriveSync] "${operationName}" failed permanently [${syncError.code}] after ${attempt} attempt(s): ${syncError.message}`
        );
        if (updateHealthOnSync) {
          updateBackupHealth({
            status: 'error',
            syncError: syncError.message,
            syncErrorCode: syncError.code,
            lastErrorAt: syncError.timestamp,
            retryAttempt: attempt - 1,
          });
        }
        throw syncError;
      }

      const delayMs = calculateBackoffDelay(
        attempt,
        baseDelayMs,
        maxDelayMs,
        retryAfterSeconds
      );
      console.warn(
        `[DriveSync] Transient error during "${operationName}" [${syncError.code}: ${syncError.message}]. Retry ${attempt}/${maxRetries} in ${delayMs}ms...`
      );
      if (updateHealthOnSync) {
        updateBackupHealth({
          status: 'syncing',
          retryAttempt: attempt,
          maxRetries,
          syncError: `Retrying (${attempt}/${maxRetries}): ${syncError.message}`,
          syncErrorCode: syncError.code,
        });
      }
      options?.onRetry?.(attempt, delayMs, syncError);
      await sleep(delayMs);
    } catch (rawErr) {
      if (rawErr instanceof DriveSyncError && !rawErr.retryable) {
        throw rawErr;
      }

      const networkError = classifyNetworkFailure(rawErr, operationName, attempt);
      if (!networkError.retryable || attempt > maxRetries) {
        const isOfflineNow = typeof navigator !== 'undefined' && navigator.onLine === false;
        console.error(
          `[DriveSync] "${operationName}" failed after ${attempt} attempt(s) [${networkError.code}]: ${networkError.message}`
        );
        if (updateHealthOnSync) {
          updateBackupHealth({
            status: isOfflineNow ? 'offline' : 'error',
            syncError: networkError.message,
            syncErrorCode: networkError.code,
            lastErrorAt: networkError.timestamp,
            retryAttempt: attempt - 1,
          });
        }
        throw networkError;
      }

      const delayMs = calculateBackoffDelay(attempt, baseDelayMs, maxDelayMs);
      console.warn(
        `[DriveSync] Network drop during "${operationName}" (${networkError.message}). Retry ${attempt}/${maxRetries} in ${delayMs}ms...`
      );
      if (updateHealthOnSync) {
        updateBackupHealth({
          status: 'syncing',
          retryAttempt: attempt,
          maxRetries,
          syncError: `Network retry (${attempt}/${maxRetries}): ${networkError.message}`,
          syncErrorCode: networkError.code,
        });
      }
      options?.onRetry?.(attempt, delayMs, networkError);
      await sleep(delayMs);
    }
  }

  throw new DriveSyncError({
    message: `Exhausted retries for ${operationName}`,
    code: 'UNKNOWN_ERROR',
    retryable: false,
    attempts: maxRetries + 1,
  });
}

// ---------------------------------------------------------------------------
// Google Drive Service
// ---------------------------------------------------------------------------
export const googleDriveService = {
  /**
   * Returns current backup health metadata (Last Synced timestamp, Sync Error status, etc.)
   */
  getBackupHealth(): DriveBackupHealthState {
    return { ...currentBackupHealth };
  },

  /**
   * Subscribes to reactive backup health state updates
   */
  subscribeBackupHealth(listener: BackupHealthListener): () => void {
    healthListeners.add(listener);
    return () => {
      healthListeners.delete(listener);
    };
  },

  /**
   * Clears the current sync error state in UI health feedback
   */
  clearSyncError(): void {
    updateBackupHealth({
      status: currentBackupHealth.lastSyncedAt ? 'synced' : 'idle',
      syncError: null,
      syncErrorCode: null,
      retryAttempt: 0,
    });
  },

  /**
   * List files from Google Drive under the least-privilege `drive.file` scope.
   * Only files created or explicitly opened by NeuroFlow are accessible.
   */
  async listFiles(
    token: string,
    search?: string,
    retryOptions?: RetryOptions
  ): Promise<DriveFile[]> {
    let query = 'trashed = false';
    if (search && search.trim()) {
      const escaped = search.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
      query += ` and name contains '${escaped}'`;
    }

    const url = new URL('https://www.googleapis.com/drive/v3/files');
    url.searchParams.set('spaces', 'drive');
    url.searchParams.set('q', query);
    url.searchParams.set('pageSize', '30');
    url.searchParams.set(
      'fields',
      'files(id,name,mimeType,modifiedTime,size,webViewLink,iconLink,thumbnailLink,starred,appProperties)'
    );
    url.searchParams.set('orderBy', 'modifiedTime desc');

    console.info(
      `[DriveSync] Listing files (scope=drive.file, search=${search ? `"${search.trim()}"` : 'none'})...`
    );

    const files = await executeDriveRequestWithRetry<DriveFile[]>(
      token,
      (activeToken) =>
        fetch(url.toString(), {
          headers: {
            Authorization: `Bearer ${activeToken}`,
          },
        }),
      async (response) => {
        const data = await response.json();
        return (data.files || []) as DriveFile[];
      },
      {
        ...retryOptions,
        operationName: 'listFiles',
      }
    );

    // Record returned file IDs in local provenance cache (all returned files are scoped by drive.file)
    recordManagedFileIds(files.map((f) => f.id));
    console.info(`[DriveSync] Listed ${files.length} app-accessible file(s) from Google Drive.`);
    return files;
  },

  /**
   * Upload a text/JSON document to Google Drive using multipart upload.
   * Stamps `NEUROFLOW_APP_PROPERTIES` metadata for explicit `drive.file` provenance.
   */
  async uploadFile(
    token: string,
    name: string,
    content: string,
    mimeType = 'text/plain',
    retryOptions?: RetryOptions & { updateHealthOnSync?: boolean }
  ): Promise<DriveFile> {
    const cleanName = (name || '').trim();
    if (!cleanName) {
      throw new DriveSyncError({
        message: 'File name is required for Google Drive upload.',
        code: 'BAD_REQUEST',
        retryable: false,
        attempts: 0,
      });
    }

    const metadata = {
      name: cleanName,
      mimeType,
      appProperties: NEUROFLOW_APP_PROPERTIES,
    };

    const boundary = '-------314159265358979323846';
    const delimiter = `\r\n--${boundary}\r\n`;
    const closeDelimiter = `\r\n--${boundary}--`;

    const multipartRequestBody =
      delimiter +
      'Content-Type: application/json; charset=UTF-8\r\n\r\n' +
      JSON.stringify(metadata) +
      delimiter +
      `Content-Type: ${mimeType}\r\n\r\n` +
      content +
      closeDelimiter;

    const uploadUrl =
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,mimeType,modifiedTime,size,webViewLink,iconLink,thumbnailLink,starred,appProperties';

    console.info(
      `[DriveSync] Uploading "${cleanName}" (${content.length} chars, mimeType=${mimeType}, scope=drive.file)...`
    );

    const createdFile = await executeDriveRequestWithRetry<DriveFile>(
      token,
      (activeToken) =>
        fetch(uploadUrl, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${activeToken}`,
            'Content-Type': `multipart/related; boundary=${boundary}`,
          },
          body: multipartRequestBody,
        }),
      async (response) => (await response.json()) as DriveFile,
      {
        ...retryOptions,
        operationName: `uploadFile(${cleanName})`,
      }
    );

    if (createdFile?.id) {
      recordManagedFileIds([createdFile.id]);
    }
    console.info(
      `[DriveSync] Uploaded "${createdFile.name}" (id=${createdFile.id}) to Google Drive.`
    );
    return createdFile;
  },

  /**
   * Backup all NeuroFlow data (tasks, routines, habits, notes) to a JSON file on Drive.
   * Updates reactive backup health state (Last Synced timestamp, Sync Error status).
   */
  async backupNeuroFlowData(
    token: string,
    appState: any,
    retryOptions?: RetryOptions
  ): Promise<DriveFile> {
    const nowIso = new Date().toISOString();
    const timestamp = nowIso.replace(/[:.]/g, '-').slice(0, 19);
    const fileName = `NeuroFlow-Backup-${timestamp}.json`;
    const content = JSON.stringify(appState, null, 2);

    console.info(`[DriveSync] Starting manual backup snapshot "${fileName}"...`);
    updateBackupHealth({
      status: 'syncing',
      syncError: null,
      syncErrorCode: null,
      retryAttempt: 0,
      maxRetries: retryOptions?.maxRetries ?? 3,
    });

    const createdFile = await this.uploadFile(token, fileName, content, 'application/json', {
      ...retryOptions,
      operationName: 'backupNeuroFlowData',
      updateHealthOnSync: true,
    });

    const syncedAt = new Date().toISOString();
    updateBackupHealth({
      status: 'synced',
      lastSyncedAt: syncedAt,
      lastBackupFileName: createdFile.name || fileName,
      lastBackupFileId: createdFile.id || null,
      syncError: null,
      syncErrorCode: null,
      retryAttempt: 0,
    });

    console.info(
      `[DriveSync] Backup snapshot "${createdFile.name}" completed at ${syncedAt}.`
    );
    return createdFile;
  },

  /**
   * Check and run automatic daily backup to Google Drive if not yet run today.
   */
  async checkAndRunAutoBackup(
    token: string,
    appState: any,
    retryOptions?: RetryOptions
  ): Promise<{ executed: boolean; fileName?: string; error?: string }> {
    const todayKey = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
    const lastBackup =
      typeof window !== 'undefined' && window.localStorage
        ? localStorage.getItem('neuroflow_last_auto_backup')
        : null;

    if (lastBackup === todayKey) {
      console.info(
        `[DriveSync] Automatic daily backup already completed for ${todayKey}. Skipping.`
      );
      return { executed: false };
    }

    const fileName = `NeuroFlow-AutoBackup-${todayKey}.json`;
    const content = JSON.stringify(appState, null, 2);

    console.info(`[DriveSync] Running automatic daily backup "${fileName}"...`);
    updateBackupHealth({
      status: 'syncing',
      syncError: null,
      syncErrorCode: null,
      retryAttempt: 0,
      maxRetries: retryOptions?.maxRetries ?? 3,
    });

    try {
      const createdFile = await this.uploadFile(
        token,
        fileName,
        content,
        'application/json',
        {
          ...retryOptions,
          operationName: 'checkAndRunAutoBackup',
          updateHealthOnSync: true,
        }
      );

      const syncedAt = new Date().toISOString();
      if (typeof window !== 'undefined' && window.localStorage) {
        localStorage.setItem('neuroflow_last_auto_backup', todayKey);
      }

      updateBackupHealth({
        status: 'synced',
        lastSyncedAt: syncedAt,
        lastBackupFileName: createdFile.name || fileName,
        lastBackupFileId: createdFile.id || null,
        syncError: null,
        syncErrorCode: null,
        retryAttempt: 0,
      });

      console.info(
        `[DriveSync] Automatic daily backup "${fileName}" succeeded at ${syncedAt}.`
      );
      return { executed: true, fileName: createdFile.name || fileName };
    } catch (err: any) {
      const errorMessage = err?.message || 'Automatic Google Drive backup failed';
      console.warn(`[DriveSync] Auto backup to Google Drive deferred: ${errorMessage}`, err);
      return { executed: false, error: errorMessage };
    }
  },

  /**
   * Delete a file from Google Drive (Caller must present user confirmation beforehand).
   * Enforces least-privilege `drive.file` provenance checks.
   */
  async deleteFile(
    token: string,
    fileId: string,
    retryOptions?: RetryOptions
  ): Promise<void> {
    const cleanId = (fileId || '').trim();
    if (!cleanId) {
      throw new DriveSyncError({
        message: 'A valid fileId is required to delete a Google Drive file.',
        code: 'BAD_REQUEST',
        retryable: false,
        attempts: 0,
      });
    }

    if (!isAppManagedDriveFile(cleanId)) {
      console.warn(
        `[DriveSync] Deleting fileId=${cleanId} not yet in local provenance cache; Google Drive API will enforce drive.file scope.`
      );
    }

    console.info(`[DriveSync] Deleting file (id=${cleanId}, scope=drive.file)...`);

    await executeDriveRequestWithRetry<void>(
      token,
      (activeToken) =>
        fetch(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(cleanId)}`, {
          method: 'DELETE',
          headers: {
            Authorization: `Bearer ${activeToken}`,
          },
        }),
      async () => undefined,
      {
        ...retryOptions,
        operationName: `deleteFile(${cleanId})`,
        allow204: true,
      }
    );

    removeManagedFileId(cleanId);
    console.info(`[DriveSync] Deleted file (id=${cleanId}) from Google Drive.`);
  },

  /**
   * Get raw content of a file from Google Drive under `drive.file` scope.
   */
  async getFileContent(
    token: string,
    fileId: string,
    retryOptions?: RetryOptions
  ): Promise<string> {
    const cleanId = (fileId || '').trim();
    if (!cleanId) {
      throw new DriveSyncError({
        message: 'A valid fileId is required to read a Google Drive file.',
        code: 'BAD_REQUEST',
        retryable: false,
        attempts: 0,
      });
    }

    console.info(`[DriveSync] Downloading file content (id=${cleanId}, scope=drive.file)...`);

    const content = await executeDriveRequestWithRetry<string>(
      token,
      (activeToken) =>
        fetch(
          `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(cleanId)}?alt=media`,
          {
            headers: {
              Authorization: `Bearer ${activeToken}`,
            },
          }
        ),
      async (response) => await response.text(),
      {
        ...retryOptions,
        operationName: `getFileContent(${cleanId})`,
      }
    );

    recordManagedFileIds([cleanId]);
    console.info(
      `[DriveSync] Downloaded file content (id=${cleanId}, length=${content.length} chars).`
    );
    return content;
  },
};
