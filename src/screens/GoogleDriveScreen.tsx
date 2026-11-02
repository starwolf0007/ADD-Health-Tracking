import React, { useState, useEffect } from 'react';
import {
  ArrowLeft,
  HardDrive,
  Search,
  Upload,
  Trash2,
  ExternalLink,
  RefreshCw,
  FileText,
  Folder,
  FileSpreadsheet,
  FileCode,
  File,
  AlertTriangle,
  CheckCircle2,
  CloudUpload,
  Plus,
  Loader2,
} from 'lucide-react';
import { useFirebaseAuth } from '../lib/firebase';
import { googleDriveService, DriveFile } from '../lib/googleDrive';
import { useNeuroStorage, exportAllData } from '../lib/storage';

interface GoogleDriveScreenProps {
  onBack: () => void;
}

export const GoogleDriveScreen: React.FC<GoogleDriveScreenProps> = ({ onBack }) => {
  const { user, accessToken, signInWithGoogle, loading: authLoading } = useFirebaseAuth();
  const storage = useNeuroStorage();

  const [files, setFiles] = useState<DriveFile[]>([]);
  const [loading, setLoading] = useState<boolean>(false);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  // New file creation modal state
  const [isCreatingFile, setIsCreatingFile] = useState<boolean>(false);
  const [newFileName, setNewFileName] = useState<string>('neuroflow-notes.md');
  const [newFileContent, setNewFileContent] = useState<string>('# Notes from NeuroFlow\n\n');
  const [isUploading, setIsUploading] = useState<boolean>(false);

  // Delete confirmation modal state (MANDATORY per workspace-integration rules)
  const [fileToDelete, setFileToDelete] = useState<DriveFile | null>(null);
  const [isDeleting, setIsDeleting] = useState<boolean>(false);

  const fetchFiles = async (token: string, search?: string) => {
    setLoading(true);
    setError(null);
    try {
      const result = await googleDriveService.listFiles(token, search);
      setFiles(result);
    } catch (err: any) {
      console.error('Failed to list files:', err);
      setError(err.message || 'Could not load Google Drive files');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (accessToken) {
      fetchFiles(accessToken, searchQuery);
    }
  }, [accessToken]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (accessToken) {
      fetchFiles(accessToken, searchQuery);
    }
  };

  const handleBackupToDrive = async () => {
    if (!accessToken) return;
    setIsUploading(true);
    setError(null);
    try {
      const backupPayload = exportAllData({ includeSensitive: false });

      const createdFile = await googleDriveService.backupNeuroFlowData(
        accessToken,
        backupPayload
      );
      setSuccessMessage(`Successfully backed up to Google Drive as "${createdFile.name}"`);
      await fetchFiles(accessToken, searchQuery);
      setTimeout(() => setSuccessMessage(null), 5000);
    } catch (err: any) {
      setError(err.message || 'Failed to backup data to Google Drive');
    } finally {
      setIsUploading(false);
    }
  };

  const handleCreateDocument = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!accessToken || !newFileName.trim()) return;
    setIsUploading(true);
    setError(null);
    try {
      await googleDriveService.uploadFile(
        accessToken,
        newFileName.trim(),
        newFileContent,
        newFileName.endsWith('.json')
          ? 'application/json'
          : newFileName.endsWith('.md')
          ? 'text/markdown'
          : 'text/plain'
      );
      setIsCreatingFile(false);
      setNewFileName('neuroflow-notes.md');
      setNewFileContent('');
      setSuccessMessage(`Created file in your Google Drive.`);
      await fetchFiles(accessToken, searchQuery);
      setTimeout(() => setSuccessMessage(null), 5000);
    } catch (err: any) {
      setError(err.message || 'Failed to create file on Google Drive');
    } finally {
      setIsUploading(false);
    }
  };

  const confirmDeleteFile = async () => {
    if (!accessToken || !fileToDelete) return;
    setIsDeleting(true);
    setError(null);
    try {
      await googleDriveService.deleteFile(accessToken, fileToDelete.id);
      setSuccessMessage(`Deleted "${fileToDelete.name}" from Google Drive.`);
      setFileToDelete(null);
      await fetchFiles(accessToken, searchQuery);
      setTimeout(() => setSuccessMessage(null), 4000);
    } catch (err: any) {
      setError(err.message || 'Failed to delete file from Google Drive');
    } finally {
      setIsDeleting(false);
    }
  };

  const getMimeIcon = (mime: string) => {
    if (mime.includes('folder')) return <Folder className="w-5 h-5 text-[#D9A441]" />;
    if (mime.includes('spreadsheet') || mime.includes('excel'))
      return <FileSpreadsheet className="w-5 h-5 text-[#2FB083]" />;
    if (mime.includes('document') || mime.includes('word') || mime.includes('text'))
      return <FileText className="w-5 h-5 text-[#4285F4]" />;
    if (mime.includes('json') || mime.includes('code'))
      return <FileCode className="w-5 h-5 text-[#BB86FC]" />;
    return <File className="w-5 h-5 text-[#8A8A8E]" />;
  };

  const formatFileSize = (bytesStr?: string) => {
    if (!bytesStr) return '';
    const bytes = parseInt(bytesStr, 10);
    if (isNaN(bytes)) return '';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / 1048576).toFixed(1)} MB`;
  };

  return (
    <div className="pb-28 max-w-2xl mx-auto px-4 pt-3 space-y-5 animate-in fade-in">
      {/* Top Header */}
      <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
        <div className="flex items-center gap-3">
          <button
            onClick={onBack}
            className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-xl"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div className="flex items-center gap-2.5">
            <div className="p-2 rounded-xl bg-[#4285F4]/15 text-[#4285F4]">
              <HardDrive className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-[#F0F0F0]">Google Drive</h2>
              <p className="text-xs text-[#8A8A8E]">Cloud Storage & Data Backup</p>
            </div>
          </div>
        </div>

        {accessToken && (
          <div className="flex items-center gap-2">
            <button
              onClick={handleBackupToDrive}
              disabled={isUploading}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#2FB083]/15 hover:bg-[#2FB083]/25 text-[#2FB083] text-xs font-semibold border border-[#2FB083]/30 transition-all shadow-sm"
              title="Backup current tasks, routines, and habits to Google Drive"
            >
              {isUploading ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <CloudUpload className="w-3.5 h-3.5" />
              )}
              <span className="hidden sm:inline">Backup to Drive</span>
            </button>

            <button
              onClick={() => setIsCreatingFile(true)}
              className="p-2 rounded-xl bg-[#1C1C1F] hover:bg-[#212124] text-[#F0F0F0] border border-[#232326] transition-colors"
              title="Create new file on Drive"
            >
              <Plus className="w-4 h-4" />
            </button>
          </div>
        )}
      </div>

      {/* Messages / Alerts */}
      {successMessage && (
        <div className="p-3 bg-[#2FB083]/15 border border-[#2FB083]/30 rounded-xl text-xs text-[#2FB083] flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4 shrink-0" />
          <span>{successMessage}</span>
        </div>
      )}

      {error && (
        <div className="p-3 bg-red-950/40 border border-red-800/40 rounded-xl text-xs text-red-300 flex items-center gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0 text-red-400" />
          <span>{error}</span>
        </div>
      )}

      {/* If Not Authenticated or Needs Drive Scopes */}
      {!accessToken ? (
        <div className="p-8 rounded-3xl bg-[#161618] border border-[#232326] text-center space-y-4 shadow-xl">
          <div className="w-16 h-16 rounded-full bg-[#4285F4]/15 text-[#4285F4] flex items-center justify-center mx-auto">
            <HardDrive className="w-8 h-8" />
          </div>
          <div>
            <h3 className="text-base font-semibold text-[#F0F0F0]">Connect Google Drive</h3>
            <p className="text-xs text-[#8A8A8E] max-w-sm mx-auto mt-1 leading-relaxed">
              Sign in to export and restore your NeuroFlow backup snapshots. NeuroFlow uses the least-privilege <code className="text-[#4285F4] font-mono">drive.file</code> scope, accessing only the files it creates.
            </p>
          </div>

          <div className="pt-2 flex justify-center">
            {/* Official Style Sign in with Google Button per spec */}
            <button
              onClick={signInWithGoogle}
              disabled={authLoading}
              className="flex items-center gap-3 px-5 py-3 rounded-2xl bg-white hover:bg-neutral-100 text-[#1F1F1F] font-semibold text-sm shadow-md transition-all active:scale-95"
            >
              <svg className="w-5 h-5" viewBox="0 0 48 48">
                <path
                  fill="#EA4335"
                  d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"
                />
                <path
                  fill="#4285F4"
                  d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"
                />
                <path
                  fill="#FBBC05"
                  d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"
                />
                <path
                  fill="#34A853"
                  d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
                />
              </svg>
              <span>Sign in with Google</span>
            </button>
          </div>
        </div>
      ) : (
        /* Connected Google Drive Workspace View */
        <div className="space-y-4">
          {/* Search bar & Refresh */}
          <form onSubmit={handleSearch} className="flex items-center gap-2">
            <div className="relative flex-1">
              <Search className="w-4 h-4 absolute left-3.5 top-3 text-[#8A8A8E]" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search files in Google Drive…"
                className="w-full bg-[#161618] text-[#F0F0F0] text-xs pl-9 pr-3 py-2.5 rounded-xl border border-[#232326] focus:border-[#4285F4] outline-none"
              />
            </div>
            <button
              type="submit"
              className="px-3.5 py-2.5 bg-[#1C1C1F] hover:bg-[#212124] text-[#F0F0F0] rounded-xl text-xs font-semibold border border-[#232326]"
            >
              Search
            </button>
            <button
              type="button"
              onClick={() => accessToken && fetchFiles(accessToken, searchQuery)}
              className="p-2.5 bg-[#1C1C1F] hover:bg-[#212124] text-[#8A8A8E] hover:text-[#F0F0F0] rounded-xl border border-[#232326]"
              title="Refresh files"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>
          </form>

          {/* Files List */}
          <div className="bg-[#161618] border border-[#232326] rounded-2xl overflow-hidden shadow-sm">
            <div className="px-4 py-2.5 border-b border-[#232326] flex items-center justify-between text-xs text-[#8A8A8E]">
              <span>Files on Google Drive</span>
              <span>{files.length} items</span>
            </div>

            {loading ? (
              <div className="p-8 text-center text-xs text-[#8A8A8E] flex flex-col items-center justify-center gap-2">
                <Loader2 className="w-5 h-5 animate-spin text-[#4285F4]" />
                <span>Loading your Drive files…</span>
              </div>
            ) : files.length === 0 ? (
              <div className="p-8 text-center text-xs text-[#8A8A8E]">
                No files found. Try backing up your data or uploading a document.
              </div>
            ) : (
              <div className="divide-y divide-[#232326] max-h-[500px] overflow-y-auto">
                {files.map((file) => (
                  <div
                    key={file.id}
                    className="p-3.5 flex items-center justify-between hover:bg-[#1C1C1F] transition-colors"
                  >
                    <div className="flex items-center gap-3 min-w-0 mr-3">
                      {getMimeIcon(file.mimeType)}
                      <div className="min-w-0">
                        <div className="flex items-center gap-1.5">
                          <h4 className="text-xs font-medium text-[#F0F0F0] truncate max-w-[220px] sm:max-w-xs">
                            {file.name}
                          </h4>
                          {file.name.startsWith('NeuroFlow-Backup') && (
                            <span className="text-[9px] px-1.5 py-0.2 rounded bg-[#2FB083]/20 text-[#2FB083] font-mono shrink-0">
                              Backup
                            </span>
                          )}
                        </div>
                        <p className="text-[11px] text-[#555559] mt-0.5">
                          {new Date(file.modifiedTime).toLocaleDateString()} ·{' '}
                          {formatFileSize(file.size)}
                        </p>
                      </div>
                    </div>

                    <div className="flex items-center gap-1 shrink-0">
                      {file.webViewLink && (
                        <a
                          href={file.webViewLink}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="p-2 text-[#8A8A8E] hover:text-[#4285F4] rounded-lg border border-transparent hover:border-[#232326]"
                          title="Open in Google Drive"
                        >
                          <ExternalLink className="w-3.5 h-3.5" />
                        </a>
                      )}

                      {/* Delete File Trigger (opens confirmation modal) */}
                      <button
                        onClick={() => setFileToDelete(file)}
                        className="p-2 text-[#8A8A8E] hover:text-red-400 rounded-lg border border-transparent hover:border-red-950"
                        title="Delete file from Google Drive"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* New File Modal */}
      {isCreatingFile && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-in fade-in">
          <div className="w-full max-w-md bg-[#161618] border border-[#232326] rounded-2xl p-5 shadow-2xl space-y-4">
            <h3 className="text-sm font-semibold text-[#F0F0F0]">Create File on Google Drive</h3>
            <form onSubmit={handleCreateDocument} className="space-y-3">
              <div>
                <label className="text-xs text-[#8A8A8E] block mb-1">File Name</label>
                <input
                  type="text"
                  value={newFileName}
                  onChange={(e) => setNewFileName(e.target.value)}
                  placeholder="document.md"
                  className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-xs px-3 py-2 rounded-xl border border-[#232326] outline-none"
                  required
                />
              </div>

              <div>
                <label className="text-xs text-[#8A8A8E] block mb-1">Content</label>
                <textarea
                  rows={5}
                  value={newFileContent}
                  onChange={(e) => setNewFileContent(e.target.value)}
                  placeholder="Write your note or notes to sync to Drive..."
                  className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-xs px-3 py-2 rounded-xl border border-[#232326] outline-none resize-none font-mono"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setIsCreatingFile(false)}
                  className="px-3 py-1.5 text-xs text-[#8A8A8E] hover:text-[#F0F0F0]"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isUploading}
                  className="px-4 py-2 bg-[#4285F4] hover:bg-[#4285F4]/90 text-white rounded-xl text-xs font-semibold"
                >
                  {isUploading ? 'Uploading…' : 'Save to Drive'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* MANDATORY USER CONFIRMATION MODAL FOR DELETIONS */}
      {fileToDelete && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm animate-in fade-in">
          <div className="w-full max-w-sm bg-[#161618] border border-red-900/50 rounded-2xl p-5 shadow-2xl space-y-3 text-center">
            <div className="w-12 h-12 rounded-full bg-red-950/60 border border-red-800 text-red-400 flex items-center justify-center mx-auto">
              <AlertTriangle className="w-6 h-6" />
            </div>

            <h3 className="text-sm font-semibold text-[#F0F0F0]">
              Delete "{fileToDelete.name}" from Google Drive?
            </h3>

            <p className="text-xs text-[#8A8A8E] leading-relaxed">
              This action will remove the file permanently from your Google Drive. This cannot be undone.
            </p>

            <div className="flex items-center justify-center gap-3 pt-3">
              <button
                onClick={() => setFileToDelete(null)}
                disabled={isDeleting}
                className="flex-1 py-2 rounded-xl bg-[#1C1C1F] hover:bg-[#212124] text-xs text-[#F0F0F0] font-medium border border-[#232326]"
              >
                Cancel
              </button>
              <button
                onClick={confirmDeleteFile}
                disabled={isDeleting}
                className="flex-1 py-2 rounded-xl bg-red-600 hover:bg-red-500 text-xs text-white font-semibold shadow-lg shadow-red-600/30"
              >
                {isDeleting ? 'Deleting…' : 'Delete File'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
