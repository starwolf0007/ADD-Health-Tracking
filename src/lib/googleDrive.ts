// Google Drive API service using client-side OAuth Bearer token

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
}

export const googleDriveService = {
  /**
   * List files from Google Drive
   */
  async listFiles(token: string, search?: string): Promise<DriveFile[]> {
    let query = "trashed = false";
    if (search && search.trim()) {
      const escaped = search.replace(/'/g, "\\'");
      query += ` and name contains '${escaped}'`;
    }

    const url = new URL('https://www.googleapis.com/drive/v3/files');
    url.searchParams.set('q', query);
    url.searchParams.set('pageSize', '30');
    url.searchParams.set(
      'fields',
      'files(id,name,mimeType,modifiedTime,size,webViewLink,iconLink,thumbnailLink,starred)'
    );
    url.searchParams.set('orderBy', 'modifiedTime desc');

    const response = await fetch(url.toString(), {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    if (!response.ok) {
      const err = await response.json();
      throw new Error(err.error?.message || 'Failed to list Google Drive files');
    }

    const data = await response.json();
    return data.files || [];
  },

  /**
   * Upload a text/JSON document to Google Drive using multipart upload
   */
  async uploadFile(
    token: string,
    name: string,
    content: string,
    mimeType = 'text/plain'
  ): Promise<DriveFile> {
    const metadata = {
      name,
      mimeType,
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

    const response = await fetch(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': `multipart/related; boundary=${boundary}`,
        },
        body: multipartRequestBody,
      }
    );

    if (!response.ok) {
      const err = await response.json();
      throw new Error(err.error?.message || 'Failed to upload file to Google Drive');
    }

    return await response.json();
  },

  /**
   * Backup all NeuroFlow data (tasks, routines, habits, notes) to a JSON file on Drive
   */
  async backupNeuroFlowData(token: string, appState: any): Promise<DriveFile> {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const fileName = `NeuroFlow-Backup-${timestamp}.json`;
    const content = JSON.stringify(appState, null, 2);

    return await this.uploadFile(token, fileName, content, 'application/json');
  },

  /**
   * Check and run automatic daily backup to Google Drive if not yet run today
   */
  async checkAndRunAutoBackup(token: string, appState: any): Promise<{ executed: boolean; fileName?: string }> {
    const todayKey = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
    const lastBackup = localStorage.getItem('neuroflow_last_auto_backup');

    if (lastBackup === todayKey) {
      return { executed: false };
    }

    try {
      const fileName = `NeuroFlow-AutoBackup-${todayKey}.json`;
      const content = JSON.stringify(appState, null, 2);
      await this.uploadFile(token, fileName, content, 'application/json');
      localStorage.setItem('neuroflow_last_auto_backup', todayKey);
      return { executed: true, fileName };
    } catch (err) {
      console.warn('Auto backup to Google Drive deferred:', err);
      return { executed: false };
    }
  },

  /**
   * Delete a file from Google Drive (Caller must present user confirmation beforehand)
   */
  async deleteFile(token: string, fileId: string): Promise<void> {
    const response = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}`, {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    if (!response.ok && response.status !== 204) {
      const err = await response.json();
      throw new Error(err.error?.message || 'Failed to delete file from Google Drive');
    }
  },

  /**
   * Get raw content of a file from Google Drive
   */
  async getFileContent(token: string, fileId: string): Promise<string> {
    const response = await fetch(
      `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      }
    );

    if (!response.ok) {
      throw new Error('Failed to read file contents from Google Drive');
    }

    return await response.text();
  },
};
