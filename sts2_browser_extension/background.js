// STS2 Mod Manager - Background Service Worker V3.2
// Handles download URL forwarding with CDN interception

const DEFAULT_PORT = 8765;
const ENDPOINTS = {
  download: '/api/download',
  status: '/api/status'
};

// Download intercept state
let interceptingDownload = false;
let pendingDownloadInfo = null;
let cachedPort = null;

// Get server port from storage (with caching)
async function getServerPort() {
  if (cachedPort !== null) return cachedPort;

  return new Promise((resolve) => {
    chrome.storage.local.get(['port'], (result) => {
      cachedPort = result.port || DEFAULT_PORT;
      console.log('[STS2-Ext] Using server port:', cachedPort);
      resolve(cachedPort);
    });
  });
}

// Build server URL with dynamic port
async function getServerUrl() {
  const port = await getServerPort();
  return `http://localhost:${port}`;
}

// Handle messages from content script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('[STS2-Ext] Received message:', message.type);

  if (message.type === 'DOWNLOAD_READY') {
    handleDownloadReady(message.data)
      .then(result => sendResponse({ success: true, data: result }))
      .catch(error => sendResponse({ success: false, error: error.message }));
    return true;
  }

  if (message.type === 'DOWNLOAD_MOD') {
    handleDownloadMod(message.data)
      .then(result => sendResponse({ success: true, data: result }))
      .catch(error => sendResponse({ success: false, error: error.message }));
    return true;
  }

  if (message.type === 'CHECK_STATUS') {
    checkServerStatus()
      .then(result => sendResponse({ success: true, data: result }))
      .catch(error => sendResponse({ success: false, error: error.message }));
    return true;
  }

  if (message.type === 'START_NXM_INTERCEPT') {
    // Content script detected NXM URL, start intercepting CDN
    pendingDownloadInfo = message.data;
    interceptingDownload = true;
    console.log('[STS2-Ext] Starting NXM intercept for:', message.data);
    sendResponse({ success: true });
    return true;
  }

  if (message.type === 'REFRESH_PORT') {
    // Force refresh port from storage
    cachedPort = null;
    getServerPort().then(port => sendResponse({ success: true, port: port }));
    return true;
  }

  return false;
});

// Listen for port storage changes
chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName === 'local' && changes.port) {
    console.log('[STS2-Ext] Port changed to:', changes.port.newValue);
    cachedPort = changes.port.newValue || DEFAULT_PORT;
  }
});

// Listen for web requests to find CDN download URLs
if (chrome.webRequest) {
  chrome.webRequest.onBeforeRequest.addListener(
    (details) => {
      if (!interceptingDownload) return null;

      const url = details.url;
      console.log('[STS2-Ext] WebRequest intercept:', url.substring(0, 100));

      // Look for CDN or direct download URLs from nexusmods
      // Also check for supporter-files.nexus-cdn.com (actual download URLs)
      if (url.includes('files.nexusmods.com') ||
          url.includes('cdn.nexusmods.com') ||
          url.includes('supporter-files.nexus-cdn.com') ||
          (url.includes('nexusmods.com') && (url.includes('.zip') || url.includes('.7z') || url.includes('.rar')))) {
        console.log('[STS2-Ext] Intercepted CDN URL:', url);
        interceptingDownload = false;

        // Send to content script
        chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
          if (tabs[0]) {
            chrome.tabs.sendMessage(tabs[0].id, {
              type: 'CDN_URL_INTERCEPTED',
              data: { url: url, info: pendingDownloadInfo }
            }).catch(err => {
              console.log('[STS2-Ext] Failed to send to tab:', err.message);
            });
          }
        });
      }

      return null;
    },
    {
      urls: ['*://files.nexusmods.com/*', '*://cdn.nexusmods.com/*', '*://supporter-files.nexus-cdn.com/*', '*://*.nexusmods.com/download*']
    },
    ['blocking']
  );
}

async function handleDownloadReady(data) {
  const { downloadUrl, modName, modId, key, expires, userId, fileId } = data;

  console.log('[STS2-Ext] Sending download URL to manager:', downloadUrl);
  console.log('[STS2-Ext] Additional params - key:', key ? key.substring(0, 10) + '...' : '', ', expires:', expires, ', user_id:', userId, ', file_id:', fileId);

  const serverUrl = await getServerUrl();
  const url = serverUrl + ENDPOINTS.download;

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        mod_id: modId,
        mod_name: modName,
        download_url: downloadUrl,
        key: key || '',
        expires: expires || 0,
        user_id: userId || 0,
        file_id: fileId || 0
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Server error: ${response.status} - ${errorText}`);
    }

    const result = await response.json();
    console.log('[STS2-Ext] Download request sent:', result);
    return result;
  } catch (error) {
    console.error('[STS2-Ext] Download failed:', error);
    throw error;
  }
}

async function handleDownloadMod(modData) {
  const serverUrl = await getServerUrl();
  const url = serverUrl + ENDPOINTS.download;

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        mod_id: modData.modId,
        mod_name: modData.modName,
        mod_page_url: modData.modPageUrl,
        version: modData.version || '',
        download_url: modData.downloadUrl || ''
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Server error: ${response.status} - ${errorText}`);
    }

    const result = await response.json();
    console.log('[STS2-Ext] Download request sent:', result);
    return result;
  } catch (error) {
    console.error('[STS2-Ext] Download failed:', error);
    throw error;
  }
}

async function checkServerStatus() {
  const serverUrl = await getServerUrl();
  const url = serverUrl + ENDPOINTS.status;

  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Server not available: ${response.status}`);
    }
    return await response.json();
  } catch (error) {
    return { running: false, error: error.message };
  }
}

// Handle extension icon click
chrome.action.onClicked.addListener(async (tab) => {
  console.log('[STS2-Ext] Extension icon clicked');
});