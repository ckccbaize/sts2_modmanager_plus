// STS2 Mod Manager - Embedded Extension for WebView2
// Bundle of content.js for direct injection into Nexus Mods pages
// Version: 4.0 - Modified for WebView2 Host Object communication

(function() {
  'use strict';

  // 防止重复加载
  if (window.STS2_EXTENSION_LOADED) {
    console.log('[STS2-Embedded] Extension already loaded, skipping');
    return;
  }

  // Mark extension as loaded
  window.STS2_EXTENSION_LOADED = true;

  console.log('[STS2-Embedded] Extension loaded on:', window.location.href);

  // Configuration - injected by BrowserHost
  const CONFIG = {
    managerUrl: 'http://localhost:8765',
    gameDomain: 'slaythespire2'
  };

  // Check if we're on the right game page
  function isTargetPage() {
    const url = window.location.href;
    return url.includes('nexusmods.com') && (
      url.includes('/' + CONFIG.gameDomain + '/') ||
      url.includes('games/' + CONFIG.gameDomain)
    );
  }

  if (!isTargetPage()) {
    console.log('[STS2-Embedded] Not a target page, skipping injection');
    return;
  }

  console.log('[STS2-Embedded] Target page detected, initializing...');

  // Track last processed URL for SPA navigation
  let lastProcessedUrl = window.location.href;

  // Main initialization function
  function initialize() {
    const pageType = getPageType();
    console.log('[STS2-Embedded] Page type:', pageType, 'URL:', window.location.href);

    // Initialize based on page type
    switch (pageType) {
      case 'download-nmm':
        handleNmmDownloadPage();
        break;
      case 'download-page':
        handleDirectDownloadPage();
        break;
      case 'files':
        initFilesPage();
        break;
      default:
        initModPage();
    }
  }

  // Detect current page type
  function getPageType() {
    const url = window.location.href;

    // Check if this is a download page with nmm=1
    if (url.includes('file_id=') && url.includes('nmm=1')) {
      return 'download-nmm';
    }

    // Regular files page
    if (url.includes('tab=files') && url.match(/\/mods\/\d+/)) {
      return 'files';
    }

    // Regular download page (without nmm=1)
    if (url.includes('file_id=') && !url.includes('nmm=1')) {
      return 'download-page';
    }

    // Mod page
    if (url.match(/\/mods\/\d+/) && !url.includes('tab=')) {
      if (document.querySelector('dd[data-id]') || document.querySelector('.file-list')) {
        return 'files';
      }
    }

    return 'mod-page';
  }

  // SPA navigation detection - monitor URL changes
  function setupSpaNavigationDetection() {
    // Monitor history changes
    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;

    history.pushState = function(...args) {
      originalPushState.apply(this, args);
      onUrlChange();
    };

    history.replaceState = function(...args) {
      originalReplaceState.apply(this, args);
      onUrlChange();
    };

    // Listen for popstate events (back/forward buttons)
    window.addEventListener('popstate', onUrlChange);

    // Also poll for URL changes (as a fallback)
    setInterval(() => {
      if (window.location.href !== lastProcessedUrl) {
        console.log('[STS2-Embedded] URL changed (detected by polling):', window.location.href);
        onUrlChange();
      }
    }, 500);
  }

  function onUrlChange() {
    const currentUrl = window.location.href;
    if (currentUrl === lastProcessedUrl) return;

    lastProcessedUrl = currentUrl;
    console.log('[STS2-Embedded] URL changed to:', currentUrl);

    if (!isTargetPage()) {
      console.log('[STS2-Embedded] New URL is not a target page');
      return;
    }

    // Wait for new page content to load
    setTimeout(() => {
      initialize();
    }, 1500);
  }

  // Initialize on load
  initialize();

  // Setup SPA navigation detection
  setupSpaNavigationDetection();

  // Also re-initialize on any significant DOM changes
  let domChangeTimeout;
  const observer = new MutationObserver((mutations) => {
    clearTimeout(domChangeTimeout);
    domChangeTimeout = setTimeout(() => {
      // Only re-initialize if we're on a mod page and haven't found the button yet
      if (!document.getElementById('sts2-download-btn')) {
        const pageType = getPageType();
        if (pageType === 'mod-page') {
          console.log('[STS2-Embedded] DOM changed, checking for mod header...');
          injectDownloadButton();
        }
      }
    }, 1000);
  });

  observer.observe(document.body, { childList: true, subtree: true });

  // ============================================
  // FILES PAGE: Inject buttons with nmm=1 logic
  // ============================================
  function initFilesPage() {
    console.log('[STS2-Embedded] Initializing Files page');

    function tryInject() {
      // 尝试多种选择器来找到文件项
      const selectors = [
        'dd.clearfix[data-id]',
        'dd[data-id]',
        '.file-item[data-id]',
        '[data-id][class*="file"]',
        'tr[data-id]',
        '[data-file-id]',
        '.file-row'
      ];

      let fileItems = [];
      for (const selector of selectors) {
        fileItems = document.querySelectorAll(selector);
        if (fileItems.length > 0) {
          console.log('[STS2-Embedded] Found file items:', fileItems.length, 'with selector:', selector);
          break;
        }
      }

      if (fileItems.length === 0) {
        console.log('[STS2-Embedded] No file items found yet, retrying in 2 seconds...');
        console.log('[STS2-Embedded] Current URL:', window.location.href);
        // 列出页面上的一些元素以便调试
        const allDataIds = document.querySelectorAll('[data-id]');
        console.log('[STS2-Embedded] Total data-id elements:', allDataIds.length);
        setTimeout(tryInject, 2000);
        return;
      }

      injectButtonsOnFilesPage();
    }

    // 延迟启动以确保页面已完全加载
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => setTimeout(tryInject, 1000));
    } else {
      setTimeout(tryInject, 1000);
      observePageChanges();
    }
  }

  function observePageChanges() {
    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            injectButtonsOnFilesPage();
          }
        }
      }
    });

    observer.observe(document.body, { childList: true, subtree: true });
  }

  function injectButtonsOnFilesPage() {
    // Nexus Mods页面可能的文件列表选择器（按优先级排序）
    const selectors = [
      'dd.clearfix[data-id]',
      'dd[data-id]',
      '.file-item[data-id]',
      '[data-id][class*="file"]',
      'tr[data-id]',
      '[data-file-id]',
      '.file-row',
      '.mod-files-list > *',
      'article[data-id]',
      '[class*="file-list"] > *',
      '[class*="files"] > [data-id]',
      'li[data-id]'
    ];

    let fileItems = [];
    for (const selector of selectors) {
      fileItems = document.querySelectorAll(selector);
      if (fileItems.length > 0) {
        console.log('[STS2-Embedded] Found', fileItems.length, 'items using selector:', selector);
        break;
      }
    }

    if (fileItems.length === 0) {
      console.log('[STS2-Embedded] No file items found with any selector');
      // Debug: log all data-id elements on page
      const allDataIds = document.querySelectorAll('[data-id]');
      console.log('[STS2-Embedded] Total elements with data-id:', allDataIds.length);
      if (allDataIds.length > 0) {
        allDataIds.forEach((el, i) => {
          if (i < 5) { // Log first 5 only
            console.log('[STS2-Embedded] data-id element:', el.tagName, el.className, el.getAttribute('data-id'));
          }
        });
      }
      return;
    }

    fileItems.forEach(item => {
      if (item.querySelector('.sts2-download-btn')) {
        return;
      }

      // 尝试多种下载列表选择器
      const listSelectors = [
        'ul.accordion-downloads',
        'ul.downloads',
        'ul.actions',
        '.download-links',
        '.file-actions',
        '[class*="download"]',
        'ul'
      ];

      let downloadList = null;
      for (const sel of listSelectors) {
        downloadList = item.querySelector(sel);
        if (downloadList) break;
      }

      if (!downloadList || downloadList.querySelector('.sts2-download-btn')) {
        return;
      }

      addSts2ButtonToFileItem(item, downloadList);
    });
  }

  function addSts2ButtonToFileItem(fileItem, downloadList) {
    const fileId = fileItem.getAttribute('data-id');
    const modIdMatch = window.location.href.match(/mods\/(\d+)/);
    const modId = modIdMatch ? modIdMatch[1] : 0;

    let modName = 'Unknown Mod';
    const titleEl = document.querySelector('.mod-intro-header h1, h1[class*="title"], .header-title h1');
    if (titleEl) {
      modName = titleEl.textContent.trim();
    }

    // Find Manual button and get its href
    const downloadLinks = downloadList.querySelectorAll('a');
    let manualLink = null;
    for (const link of downloadLinks) {
      const text = link.textContent.trim().toLowerCase();
      if (text.includes('manual')) {
        manualLink = link;
        break;
      }
    }

    let downloadUrl = '';
    if (manualLink) {
      const href = manualLink.getAttribute('href') || '';
      if (href) {
        const urlObj = new URL(href, window.location.origin);
        urlObj.searchParams.set('nmm', '1');
        downloadUrl = urlObj.toString();
      }
    } else {
      downloadUrl = `https://www.nexusmods.com/slaythespire2/mods/${modId}?tab=files&file_id=${fileId}&nmm=1`;
    }

    const btn = document.createElement('li');
    btn.className = 'sts2-download-btn-wrapper';

    const link = document.createElement('a');
    link.className = 'sts2-download-btn btn inline-flex';
    link.href = downloadUrl;

    link.innerHTML = `
      <svg class="icon" style="width:16px;height:16px;vertical-align:middle;margin-right:6px"><use xlink:href="/assets/images/icons/icons.svg#icon-download"></use></svg>
      <span class="flex-label">Mod manager download</span>
    `;

    link.style.cssText = `
      background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
      color: white;
      border: none;
      border-radius: 4px;
      padding: 6px 12px;
      font-size: 12px;
      font-weight: 500;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.2s ease;
      text-decoration: none;
    `;

    link.addEventListener('mouseenter', () => {
      link.style.transform = 'translateY(-1px)';
      link.style.boxShadow = '0 2px 8px rgba(99, 102, 241, 0.4)';
    });

    link.addEventListener('mouseleave', () => {
      link.style.transform = 'translateY(0)';
      link.style.boxShadow = 'none';
    });

    btn.appendChild(link);
    downloadList.appendChild(btn);

    console.log('[STS2-Embedded] Added button for file_id:', fileId);
  }

  // ============================================
  // NMM DOWNLOAD PAGE: Extract NXM URL
  // ============================================
  function handleNmmDownloadPage() {
    console.log('[STS2-Embedded] Handling NMM download page');

    showStatusMessage('Getting download link...');

    const modIdMatch = window.location.href.match(/mods\/(\d+)/);
    const fileIdMatch = window.location.href.match(/file_id=(\d+)/);
    const modId = modIdMatch ? modIdMatch[1] : 0;
    const fileId = fileIdMatch ? fileIdMatch[1] : 0;

    let modName = 'Unknown Mod';
    const titleEl = document.querySelector('h1, .mod-title, .mod-intro-header h1');
    if (titleEl) {
      modName = titleEl.textContent.trim();
    }

    waitForNxmLink(modId, fileId, modName);
  }

  function waitForNxmLink(modId, fileId, modName) {
    console.log('[STS2-Embedded] Waiting for NXM link...');

    showStatusMessage('Please click the download button to get the link...');

    let foundUrl = null;

    const extractFromHtml = () => {
      const html = document.body.innerHTML || '';
      const match = html.match(/nxm:\/\/[^\s<>'"\])}]*/);
      if (match) {
        return match[0];
      }
      const text = document.body.textContent || '';
      const textMatch = text.match(/nxm:\/\/[^\s<>'"\])}]*/);
      if (textMatch) {
        return textMatch[0];
      }
      return null;
    };

    foundUrl = extractFromHtml();
    if (foundUrl) {
      console.log('[STS2-Embedded] Found NXM URL:', foundUrl);
      showStatusMessage('Found download link, sending...');
      sendNxmDownloadUrl(foundUrl, modId, parseInt(fileId), modName);
      return;
    }

    const observer = new MutationObserver(() => {
      const url = extractFromHtml();
      if (url && !foundUrl) {
        console.log('[STS2-Embedded] Found NXM URL via observer:', url);
        foundUrl = url;
        observer.disconnect();
        showStatusMessage('Found download link, sending...');
        sendNxmDownloadUrl(foundUrl, modId, parseInt(fileId), modName);
      }
    });

    observer.observe(document.body, { childList: true, subtree: true, characterData: true });

    let attempts = 0;
    const poll = () => {
      if (foundUrl) {
        observer.disconnect();
        return;
      }

      attempts++;
      const url = extractFromHtml();
      if (url) {
        console.log('[STS2-Embedded] Found NXM URL via poll:', url);
        foundUrl = url;
        observer.disconnect();
        showStatusMessage('Found download link, sending...');
        sendNxmDownloadUrl(foundUrl, modId, parseInt(fileId), modName);
        return;
      }

      if (attempts < 60) {
        setTimeout(poll, 500);
      } else {
        console.log('[STS2-Embedded] Timeout after 30s');
        observer.disconnect();
        showStatusMessage('Timeout, please try again', 'error');
      }
    };

    poll();
  }

  // ============================================
  // DIRECT DOWNLOAD PAGE
  // ============================================
  function handleDirectDownloadPage() {
    console.log('[STS2-Embedded] Handling direct download page');
    showStatusMessage('Waiting for download page...');

    const modIdMatch = window.location.href.match(/mods\/(\d+)/);
    const fileIdMatch = window.location.href.match(/file_id=(\d+)/);
    const modId = modIdMatch ? modIdMatch[1] : 0;
    const fileId = fileIdMatch ? fileIdMatch[1] : 0;

    let modName = 'Unknown Mod';
    const titleEl = document.querySelector('h1, .mod-title, .mod-intro-header h1');
    if (titleEl) {
      modName = titleEl.textContent.trim();
    }

    waitForDownloadLink(modId, fileId, modName);
  }

  function waitForDownloadLink(modId, fileId, modName) {
    let pollCount = 0;
    const maxPolls = 30;
    const pollInterval = 500;

    const checkAndFetch = async () => {
      pollCount++;
      console.log('[STS2-Embedded] Checking for download link, attempt:', pollCount);

      const links = document.querySelectorAll('a');
      let clickHereLink = null;

      for (const link of links) {
        const text = link.textContent.trim().toLowerCase();
        if (text.includes('click here') || (text.includes('click') && text.includes('here'))) {
          clickHereLink = link;
          break;
        }
      }

      if (clickHereLink && clickHereLink.href) {
        const actualUrl = clickHereLink.href;
        if (actualUrl.includes('nexus-cdn.com') || actualUrl.includes('files.nexusmods.com') ||
            actualUrl.endsWith('.zip') || actualUrl.endsWith('.7z') || actualUrl.endsWith('.rar')) {
          console.log('[STS2-Embedded] Found direct download URL:', actualUrl);
          sendDownloadUrl(actualUrl, modId, modName);
          return;
        }
      }

      for (const link of links) {
        const href = link.href || '';
        if (href.includes('md5=') || (href.includes('expires=') && href.includes('user_id='))) {
          if (href.includes('nexus-cdn.com') || href.includes('.zip') || href.includes('.7z')) {
            sendDownloadUrl(href, modId, modName);
            return;
          }
        }
      }

      if (pollCount < maxPolls) {
        setTimeout(checkAndFetch, pollInterval);
      } else {
        console.log('[STS2-Embedded] Max polls reached, trying fallback...');
        showStatusMessage('Could not find download link, trying API...', 'error');
        sendDownloadUrl('nxm://slaythespire2/mods/' + modId + '/files/' + fileId, modId, modName);
      }
    };

    setTimeout(checkAndFetch, 1000);
  }

  // ============================================
  // Send download requests via WebView2 Host Object
  // ============================================
  async function sendNxmDownloadUrl(nxmUrl, modId, fileId, modName) {
    console.log('[STS2-Embedded] Sending NXM URL:', nxmUrl);

    let key = '';
    let expires = 0;
    let userId = 0;

    try {
      const decodedUrl = nxmUrl.replace(/&amp;/g, '&');
      const urlObj = new URL(decodedUrl);
      key = urlObj.searchParams.get('key') || '';
      expires = parseInt(urlObj.searchParams.get('expires') || '0');
      userId = parseInt(urlObj.searchParams.get('user_id') || '0');

      const pathMatch = nxmUrl.match(/\/files\/(\d+)/);
      if (pathMatch) {
        fileId = parseInt(pathMatch[1]);
      }
    } catch (e) {
      console.log('[STS2-Embedded] Failed to parse NXM URL:', e);
    }

    showStatusMessage('Sending to Mod Manager...');

    // Build JSON payload for sync COM call
    // Use snake_case field names to match backend API expectations
    const requestData = JSON.stringify({
      type: 'nxm',
      mod_id: modId,
      mod_name: modName,
      file_id: fileId,
      nxm_url: nxmUrl,
      key: key,
      expires: expires,
      user_id: userId
    });

    // Send via WebView2 Host Object using sync call
    try {
      if (window.chrome && window.chrome.webview && window.chrome.webview.hostObjects &&
          window.chrome.webview.hostObjects.browserHost) {
        // Use sync call with JSON string parameter
        window.chrome.webview.hostObjects.browserHost.SendDownloadRequest(requestData);
        showStatusMessage('Sent to Mod Manager!', 'success');
      } else {
        // Fallback: use fetch to local API
        const response = await fetch(CONFIG.managerUrl + '/api/download', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: requestData
        });

        if (response.ok) {
          showStatusMessage('Sent to Mod Manager!', 'success');
        } else {
          throw new Error('Failed to send');
        }
      }
    } catch (error) {
      console.error('[STS2-Embedded] Failed to send:', error);
      showStatusMessage('Failed to send to Mod Manager', 'error');
    }
  }

  async function sendDownloadUrl(downloadUrl, modId, modName) {
    showStatusMessage('Sending to Mod Manager...');

    const requestData = JSON.stringify({
      type: 'direct',
      mod_id: modId,
      mod_name: modName,
      download_url: downloadUrl
    });

    try {
      if (window.chrome && window.chrome.webview && window.chrome.webview.hostObjects &&
          window.chrome.webview.hostObjects.browserHost) {
        // Use sync call with JSON string parameter
        window.chrome.webview.hostObjects.browserHost.SendDownloadRequest(requestData);
        showStatusMessage('Sent to Mod Manager!', 'success');
      } else {
        const response = await fetch(CONFIG.managerUrl + '/api/download', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: requestData
        });

        if (response.ok) {
          showStatusMessage('Sent to Mod Manager!', 'success');
        } else {
          throw new Error('Failed to send');
        }
      }
    } catch (error) {
      console.error('[STS2-Embedded] Failed to send:', error);
      showStatusMessage('Failed to send to Mod Manager', 'error');
    }
  }

  // ============================================
  // MOD PAGE: Add download button
  // ============================================
  function initModPage() {
    console.log('[STS2-Embedded] Initializing mod page');

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', injectDownloadButton);
    } else {
      injectDownloadButton();
    }
  }

  function injectDownloadButton() {
    const modHeader = document.querySelector('.mod-header, .mod-title, h1.mod-name, [class*="header"]');
    if (!modHeader) {
      console.log('[STS2-Embedded] Could not find mod header');
      setTimeout(injectDownloadButton, 2000);
      return;
    }

    if (document.getElementById('sts2-download-btn')) {
      return;
    }

    const btn = document.createElement('button');
    btn.id = 'sts2-download-btn';
    btn.className = 'sts2-download-btn';
    btn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
        <polyline points="7 10 12 15 17 10"/>
        <line x1="12" y1="15" x2="12" y2="3"/>
      </svg>
      Download to STS2 Manager
    `;

    btn.style.cssText = `
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 10px 20px;
      background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s ease;
      box-shadow: 0 4px 12px rgba(99, 102, 241, 0.3);
      margin-left: 12px;
      vertical-align: middle;
    `;

    btn.onmouseover = () => {
      btn.style.transform = 'translateY(-2px)';
      btn.style.boxShadow = '0 6px 16px rgba(99, 102, 241, 0.4)';
    };

    btn.onmouseout = () => {
      btn.style.transform = 'translateY(0)';
      btn.style.boxShadow = '0 4px 12px rgba(99, 102, 241, 0.3)';
    };

    btn.onclick = () => downloadMod(btn);

    const downloadSection = document.querySelector('.mod-description, .file-actions, [class*="download"], .header-actions');
    if (downloadSection) {
      downloadSection.parentNode.insertBefore(btn, downloadSection);
    } else if (modHeader) {
      modHeader.parentNode.insertBefore(btn, modHeader.nextSibling);
    }

    console.log('[STS2-Embedded] Download button injected');
  }

  async function downloadMod(btn) {
    const originalText = btn.innerHTML;
    btn.innerHTML = 'Sending...';
    btn.disabled = true;

    try {
      const modData = getModData();
      console.log('[STS2-Embedded] Sending download request:', modData);

      const requestData = JSON.stringify({
        type: 'mod',
        modId: modData.modId,
        modName: modData.modName,
        modPageUrl: modData.modPageUrl,
        version: modData.version
      });

      if (window.chrome && window.chrome.webview && window.chrome.webview.hostObjects &&
          window.chrome.webview.hostObjects.browserHost) {
        // Use sync call with JSON string parameter
        window.chrome.webview.hostObjects.browserHost.SendDownloadRequest(requestData);

        btn.innerHTML = 'Sent to Manager!';
        btn.style.background = '#22c55e';
        setTimeout(() => {
          btn.innerHTML = originalText;
          btn.style.background = '';
          btn.disabled = false;
        }, 3000);
      } else {
        const response = await fetch(CONFIG.managerUrl + '/api/download', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: requestData
        });

        if (response.ok) {
          btn.innerHTML = 'Sent to Manager!';
          btn.style.background = '#22c55e';
          setTimeout(() => {
            btn.innerHTML = originalText;
            btn.style.background = '';
            btn.disabled = false;
          }, 3000);
        } else {
          throw new Error('Failed to send');
        }
      }
    } catch (error) {
      console.error('[STS2-Embedded] Download error:', error);
      btn.innerHTML = 'Failed';
      btn.style.background = '#ef4444';
      setTimeout(() => {
        btn.innerHTML = originalText;
        btn.style.background = '';
        btn.disabled = false;
      }, 3000);
    }
  }

  function getModData() {
    const modIdMatch = window.location.href.match(/mods\/(\d+)/);
    const modId = modIdMatch ? parseInt(modIdMatch[1]) : 0;

    let modName = '';
    const nameEl = document.querySelector('h1.mod-name, .mod-header h1, h1[class*="title"]');
    if (nameEl) modName = nameEl.textContent.trim();

    let version = '';
    const versionEl = document.querySelector('[class*="version"], .mod-version, .file-version');
    if (versionEl) version = versionEl.textContent.trim().replace('Version:', '').trim();

    return {
      modId,
      modName: modName || 'Unknown Mod',
      modPageUrl: window.location.href,
      version: version || '',
      downloadUrl: ''
    };
  }

  // ============================================
  // UI Helper
  // ============================================
  function showStatusMessage(message, type = 'info') {
    const existing = document.getElementById('sts2-status');
    if (existing) existing.remove();

    const statusEl = document.createElement('div');
    statusEl.id = 'sts2-status';

    const bgColor = type === 'success' ? '#22c55e' : type === 'error' ? '#ef4444' : '#6366f1';
    const icon = type === 'success' ? '✓' : type === 'error' ? '✕' : '⏳';

    statusEl.innerHTML = `
      <div style="
        position: fixed;
        top: 20px;
        right: 20px;
        padding: 16px 24px;
        background: ${bgColor};
        color: white;
        border-radius: 8px;
        font-family: system-ui, -apple-system, sans-serif;
        font-size: 14px;
        z-index: 99999;
        box-shadow: 0 4px 20px rgba(0,0,0,0.3);
        display: flex;
        align-items: center;
        gap: 12px;
        animation: sts2SlideIn 0.3s ease;
      ">
        <span style="font-size: 18px;">${icon}</span>
        <span>${message}</span>
      </div>
      <style>
        @keyframes sts2SlideIn {
          from { transform: translateX(100%); opacity: 0; }
          to { transform: translateX(0); opacity: 1; }
        }
      </style>
    `;

    document.body.appendChild(statusEl);

    if (type !== 'success') {
      setTimeout(() => {
        if (statusEl.parentNode) {
          statusEl.remove();
        }
      }, 10000);
    }
  }

  console.log('[STS2-Embedded] Initialization complete');

})();
