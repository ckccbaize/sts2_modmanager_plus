using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.Core;
using System.Threading;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;

namespace BrowserHost
{
    // Aria2 HTTP API Server (�� Godot ����)
    internal class Aria2ApiServer
    {
        private HttpListener? _listener;
        private BrowserHostObject? _browserHost;
        private CancellationTokenSource? _cts;
        private readonly int _port;

        public Aria2ApiServer(int port = 18765)
        {
            _port = port;
        }

        public void Start(BrowserHostObject browserHost)
        {
            _browserHost = browserHost;
            _listener = new HttpListener();
            _listener.Prefixes.Add($"http://localhost:{_port}/");
            _cts = new CancellationTokenSource();

            try
            {
                _listener.Start();
                Console.WriteLine($"[Aria2ApiServer] Started on port {_port}");
                Task.Run(() => ListenAsync(_cts.Token));
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Aria2ApiServer] Failed to start: {ex.Message}");
            }
        }

        public void Stop()
        {
            _cts?.Cancel();
            _listener?.Stop();
            Console.WriteLine("[Aria2ApiServer] Stopped");
        }

        private async Task ListenAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested && _listener?.IsListening == true)
            {
                try
                {
                    var context = await _listener.GetContextAsync();
                    _ = Task.Run(() => HandleRequest(context), ct);
                }
                catch { }
            }
        }

        private void HandleRequest(HttpListenerContext context)
        {
            try
            {
                var path = context.Request.Url?.AbsolutePath ?? "";
                var method = context.Request.HttpMethod;

                Console.WriteLine($"[Aria2ApiServer] {method} {path}");

                if (path == "/aria2-download" && method == "POST")
                {
                    using var reader = new StreamReader(context.Request.InputStream);
                    var body = reader.ReadToEnd();
                    Console.WriteLine($"[Aria2ApiServer] Body: {body}");

                    try
                    {
                        var doc = System.Text.Json.JsonDocument.Parse(body);
                        var url = doc.RootElement.TryGetProperty("url", out var u) ? u.GetString() : "";
                        var savePath = doc.RootElement.TryGetProperty("save_path", out var sp) ? sp.GetString() : "";

                        if (!string.IsNullOrEmpty(url) && !string.IsNullOrEmpty(savePath) && _browserHost != null)
                        {
                            var gid = _browserHost.AddAria2Download(url, savePath);
                            var response = new { success = gid != null, gid = gid ?? "" };
                            SendJson(context, 200, response);
                            Console.WriteLine($"[Aria2ApiServer] Download started: {gid}");
                        }
                        else
                        {
                            SendJson(context, 400, new { error = "url and save_path required" });
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[Aria2ApiServer] Error: {ex.Message}");
                        SendJson(context, 500, new { error = ex.Message });
                    }
                }
                else if (path == "/aria2-status" && method == "GET")
                {
                    var running = _browserHost?.aria2Manager?.IsRunning ?? false;
                    SendJson(context, 200, new { running = running });
                }
                else
                {
                    SendJson(context, 404, new { error = "Not found" });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Aria2ApiServer] Handle error: {ex.Message}");
            }
        }

        private void SendJson(HttpListenerContext context, int statusCode, object data)
        {
            context.Response.StatusCode = statusCode;
            context.Response.ContentType = "application/json";
            var json = System.Text.Json.JsonSerializer.Serialize(data);
            var buffer = Encoding.UTF8.GetBytes(json);
            context.Response.OutputStream.Write(buffer, 0, buffer.Length);
            context.Response.Close();
        }
    }

    internal static class NativeMethods
    {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    }

    // Host object exposed to JavaScript via AddHostObjectToScript
    [ComVisible(true)]
    public class BrowserHostObject
    {
        public Aria2Manager? aria2Manager { get; set; }
        public Microsoft.Web.WebView2.WinForms.WebView2? _webView { get; set; }  // ����ִ�� JavaScript

        // Aria2 ��ݷ���
        public bool Start(string aria2Path)
        {
            if (aria2Manager != null)
            {
                return aria2Manager.Start(aria2Path);
            }
            return false;
        }

        // ֪ͨ WebUI ��װ��ɣ��� Godot ���ã�
        public void NotifyInstallComplete(string modName, string downloadId)
        {
            Console.WriteLine($"[BrowserHostObject] NotifyInstallComplete: {modName}, id={downloadId}");
            Program.NotifyWebUIOfInstallComplete(modName, downloadId);
        }

        // ִ�� JavaScript �����ؽ�����첽��
        public async Task<string?> ExecuteScriptAsync(string script)
        {
            if (_webView?.CoreWebView2 == null)
            {
                Console.WriteLine("[BrowserHostObject] ExecuteScriptAsync: WebView not available");
                return null;
            }

            try
            {
                var result = await _webView.CoreWebView2.ExecuteScriptAsync(script);
                Console.WriteLine($"[BrowserHostObject] ExecuteScriptAsync result: {result}");
                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHostObject] ExecuteScriptAsync error: {ex.Message}");
                return null;
            }
        }

        // ͬ��ִ�� JavaScript������ Host Object ������
        public string ExecuteScript(string script)
        {
            if (_webView?.CoreWebView2 == null)
            {
                Console.WriteLine("[BrowserHostObject] ExecuteScript: WebView not available");
                return "null";
            }

            try
            {
                var result = _webView.CoreWebView2.ExecuteScriptAsync(script).GetAwaiter().GetResult();
                return result ?? "null";
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHostObject] ExecuteScript error: {ex.Message}");
                return "null";
            }
        }

        // ��ʾ�������֪ͨ�� WebUI
        public void NotifyDownloadComplete(string modName, string downloadId)
        {
            Console.WriteLine($"[BrowserHostObject] NotifyDownloadComplete: {modName}, id={downloadId}");
            var escapedName = modName.Replace("'", "\\'").Replace("\"", "\\\"").Replace("\n", " ").Replace("\r", "");
            var escapedId = downloadId.Replace("'", "\\'").Replace("\"", "\\\"");
            var script = $@"
                (function() {{
                    if (window.app && window.app.notifications) {{
                        window.app.notifications.show('�������: {escapedName}', 'success', 3000);
                    }}
                    if (window.STS2Downloads) {{
                        window.STS2Downloads.onBackendDownloadComplete('{escapedId}', '{escapedName}');
                    }}
                    console.log('[BrowserHost] Download complete notified: {escapedName}');
                }})();
            ";
            ExecuteScript(script);
        }

        // ���� WebUI �� DPI ���ţ��� Godot ���ã�
        public void SetDpiScale(double scale)
        {
            Console.WriteLine($"[BrowserHostObject] SetDpiScale: {scale}");
            var script = $@"
                (function() {{
                    if (window.app && window.app.applyDpiScale) {{
                        window.app.applyDpiScale({scale});
                    }}
                }})();
            ";
            ExecuteScript(script);
        }

        // ��ȡȫ��ѡ��
        public async Task<object> GetGlobalOptionsAsync()
        {
            if (aria2Manager != null)
            {
                return await aria2Manager.GetGlobalOptionsAsync();
            }
            return new Dictionary<string, string>();
        }

        // ���� Aria2 ���أ��� Godot ���ã�
        public string? AddAria2Download(string url, string savePath)
        {
            if (aria2Manager == null || !aria2Manager.IsRunning)
            {
                Console.WriteLine("[BrowserHost] AddAria2Download: Aria2 not running");
                return null;
            }

            try
            {
                var options = new Dictionary<string, string>
                {
                    { "out", Path.GetFileName(savePath) },
                    { "dir", Path.GetDirectoryName(savePath) ?? "." }
                };

                var gid = aria2Manager.AddDownloadAsync(url, savePath, options).GetAwaiter().GetResult();
                Console.WriteLine($"[BrowserHost] AddAria2Download: started {gid}");
                return gid;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] AddAria2Download error: {ex.Message}");
                return null;
            }
        }

        // ���µ����ص�
        private Action<string, string, string, string>? _showUpdateDialogCallback;
        // �����ص�
        private Action<string>? _navigateCallback;

        public void SetUpdateDialogCallback(Action<string, string, string, string> callback)
        {
            _showUpdateDialogCallback = callback;
        }

        public void SetNavigateCallback(Action<string> callback)
        {
            _navigateCallback = callback;
        }

        public void ShowUpdateDialog(string currentVersion, string newVersion, string changelog, string downloadUrl)
        {
            Console.WriteLine($"[BrowserHost] ShowUpdateDialog called: {currentVersion} -> {newVersion}");
            _showUpdateDialogCallback?.Invoke(currentVersion, newVersion, changelog, downloadUrl);
        }

        public string SelectFolder()
        {
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = "ѡ�񵼳�Ŀ¼";
                dialog.UseDescriptionForTitle = true;
                dialog.ShowNewFolderButton = true;
                if (dialog.ShowDialog() == DialogResult.OK)
                {
                    return dialog.SelectedPath;
                }
            }
            return null;
        }

        // ѡ�񱾵� ZIP �ļ����е���
        public string SelectBundleFile()
        {
            using (var dialog = new OpenFileDialog())
            {
                dialog.Filter = "���ϰ��ļ� (*.zip)|*.zip|�����ļ� (*.*)|*.*";
                dialog.Title = "ѡ�����ϰ�";
                dialog.CheckFileExists = true;
                dialog.CheckPathExists = true;
                if (dialog.ShowDialog() == DialogResult.OK)
                {
                    Console.WriteLine($"[BrowserHost] SelectBundleFile: {dialog.FileName}");
                    return dialog.FileName;
                }
            }
            return null;
        }

        // Navigate to Nexus Mods website - synchronous for COM interop
        public void NavigateToNexus()
        {
            Console.WriteLine("[BrowserHost] NavigateToNexus called");
            try
            {
                // Use the stored navigation callback if available
                if (_navigateCallback != null)
                {
                    _navigateCallback("https://www.nexusmods.com/slaythespire2");
                    Console.WriteLine("[BrowserHost] NavigateToNexus: using callback");
                    return;
                }

                // Fallback: try to find WebView2 via Application.OpenForms
                var form = Application.OpenForms[0];
                if (form != null)
                {
                    // Look for WebView2 in all controls recursively
                    var webView = FindWebView2(form);
                    if (webView != null && webView.CoreWebView2 != null)
                    {
                        webView.CoreWebView2.Navigate("https://www.nexusmods.com/slaythespire2");
                        Console.WriteLine("[BrowserHost] NavigateToNexus: navigated via fallback");
                    }
                    else
                    {
                        Console.WriteLine("[BrowserHost] NavigateToNexus: WebView2 not found in form");
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] NavigateToNexus error: {ex.Message}");
            }
        }

        // Navigate back to local Web UI - synchronous for COM interop
        public void NavigateToLocalhost()
        {
            Console.WriteLine("[BrowserHost] NavigateToLocalhost called");
            try
            {
                // ȡ���κι���� HTTP ���󣬷�ֹ�̳߳ؼ���
                Program.CancelPendingRequests();

                var port = Program.GetCurrentPort();

                // ʹ�� hash ·�� #mods������������ index.html��JavaScript ��� hash �л�ҳ��
                var targetUrl = $"http://localhost:{port}/index.html#mods";

                // Use the stored navigation callback if available
                if (_navigateCallback != null)
                {
                    _navigateCallback(targetUrl);
                    Console.WriteLine("[BrowserHost] NavigateToLocalhost: using callback, target:", targetUrl);
                    return;
                }

                // Fallback: try to find WebView2 via Application.OpenForms
                var form = Application.OpenForms[0];
                if (form != null)
                {
                    var webView = FindWebView2(form);
                    if (webView != null && webView.CoreWebView2 != null)
                    {
                        webView.CoreWebView2.Navigate(targetUrl);
                        Console.WriteLine("[BrowserHost] NavigateToLocalhost: navigated via fallback");
                    }
                    else
                    {
                        Console.WriteLine("[BrowserHost] NavigateToLocalhost: WebView2 not found in form");
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] NavigateToLocalhost error: {ex.Message}");
            }
        }

        // Helper method to find WebView2 recursively
        private Microsoft.Web.WebView2.WinForms.WebView2 FindWebView2(Control parent)
        {
            if (parent is Microsoft.Web.WebView2.WinForms.WebView2 webView)
                return webView;

            foreach (Control child in parent.Controls)
            {
                var result = FindWebView2(child);
                if (result != null)
                    return result;
            }
            return null;
        }

        // Send download request from Nexus page to Godot backend - synchronous for COM interop
        public void SendDownloadRequest(string jsonData)
        {
            try
            {
                Console.WriteLine($"[BrowserHost] SendDownloadRequest called");
                Console.WriteLine($"[BrowserHost] Download request: {jsonData?.Substring(0, Math.Min(200, jsonData?.Length ?? 0))}...");

                // ��������
                var doc = System.Text.Json.JsonDocument.Parse(jsonData ?? "{}");
                var root = doc.RootElement;
                var downloadType = root.TryGetProperty("type", out var t) ? t.GetString() : "";
                var modName = root.TryGetProperty("mod_name", out var mn) ? mn.GetString() : "mod";
                var downloadUrl = root.TryGetProperty("download_url", out var du) ? du.GetString() : "";

                // �����ֱ�� URL������ʹ�� Aria2 ����
                if (!string.IsNullOrEmpty(downloadUrl) && downloadUrl.StartsWith("http"))
                {
                    Console.WriteLine($"[BrowserHost] Using Aria2 for direct URL download");

                    // ��������·��
                    var safeName = modName.Replace("/", "_").Replace("\\", "_").Replace(":", "_")
                        .Replace("*", "_").Replace("?", "_").Replace("\"", "_")
                        .Replace("<", "_").Replace(">", "_").Replace("|", "_");
                    var downloadsDir = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                        "Downloads", "STS2Mods");
                    Directory.CreateDirectory(downloadsDir);
                    var savePath = Path.Combine(downloadsDir, safeName + ".zip");

                    // ʹ�� Aria2 ����
                    if (aria2Manager != null && aria2Manager.IsRunning)
                    {
                        var options = new Dictionary<string, string>
                        {
                            { "out", Path.GetFileName(savePath) },
                            { "dir", Path.GetDirectoryName(savePath) ?? downloadsDir }
                        };

                        try
                        {
                            var gid = aria2Manager.AddDownloadAsync(downloadUrl, savePath, options).GetAwaiter().GetResult();
                            if (!string.IsNullOrEmpty(gid))
                            {
                                Console.WriteLine($"[BrowserHost] Aria2 download started: {gid}");

                                // ֪ͨ Godot �����ѿ�ʼ
                                ForwardToGodot(jsonData, gid, "aria2");
                            }
                            else
                            {
                                Console.WriteLine($"[BrowserHost] Aria2 AddDownload failed");
                                // ������ Godot ����
                                ForwardToGodot(jsonData, null, "fallback");
                            }
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"[BrowserHost] Aria2 error: {ex.Message}");
                            ForwardToGodot(jsonData, null, "error");
                        }
                    }
                    else
                    {
                        Console.WriteLine($"[BrowserHost] Aria2 not running, forwarding to Godot");
                        ForwardToGodot(jsonData, null, "no-aria2");
                    }
                    return;
                }

                // ���� NXM URL��ֱ��ת���� Godot ����
                // Godot �������� Nexus API ��֤�����Ի�ȡ��ʵ�������Ӻ��ٵ��� Aria2
                Console.WriteLine($"[BrowserHost] NXM URL detected, forwarding to Godot for processing");
                ForwardToGodot(jsonData, null, "nxm-forward");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] SendDownloadRequest error: {ex.Message}");
            }
        }

        private async void _ProcessNxmWithAria2(string jsonData)
        {
            try
            {
                var doc = System.Text.Json.JsonDocument.Parse(jsonData ?? "{}");
                var root = doc.RootElement;

                var modId = root.TryGetProperty("mod_id", out var mi) ? mi.GetInt32() : 0;
                var fileId = root.TryGetProperty("file_id", out var fi) ? fi.GetInt32() : 0;
                var modName = root.TryGetProperty("mod_name", out var mn) ? mn.GetString() : "mod";
                var apiKey = root.TryGetProperty("key", out var ak) ? ak.GetString() : "";
                var expires = root.TryGetProperty("expires", out var exp) ? exp.GetInt64() : 0;
                var userId = root.TryGetProperty("user_id", out var uid) ? uid.GetInt64() : 0;

                if (modId == 0 || fileId == 0)
                {
                    Console.WriteLine($"[BrowserHost] Invalid NXM params, forwarding to Godot");
                    ForwardToGodot(jsonData, null, "invalid-nxm");
                    return;
                }

                // ���� Nexus API ��ȡ��ʵ��������
                Console.WriteLine($"[BrowserHost] Getting download link from Nexus API: mod={modId}, file={fileId}");
                var downloadUrl = await _GetNexusDownloadLink(modId, fileId, apiKey, expires, userId);

                if (string.IsNullOrEmpty(downloadUrl))
                {
                    Console.WriteLine($"[BrowserHost] Failed to get download link, forwarding to Godot");
                    ForwardToGodot(jsonData, null, "api-failed");
                    return;
                }

                Console.WriteLine($"[BrowserHost] Got download URL, using Aria2");

                // ʹ�� Aria2 ����
                var safeName = modName.Replace("/", "_").Replace("\\", "_").Replace(":", "_")
                    .Replace("*", "_").Replace("?", "_").Replace("\"", "_")
                    .Replace("<", "_").Replace(">", "_").Replace("|", "_");
                var downloadsDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    "Downloads", "STS2Mods");
                Directory.CreateDirectory(downloadsDir);
                var savePath = Path.Combine(downloadsDir, safeName + ".zip");

                if (aria2Manager != null && aria2Manager.IsRunning)
                {
                    var options = new Dictionary<string, string>
                    {
                        { "out", Path.GetFileName(savePath) },
                        { "dir", Path.GetDirectoryName(savePath) ?? downloadsDir }
                    };

                    var gid = await aria2Manager.AddDownloadAsync(downloadUrl, savePath, options);
                    if (!string.IsNullOrEmpty(gid))
                    {
                        Console.WriteLine($"[BrowserHost] Aria2 download started via NXM: {gid}");
                        ForwardToGodot(jsonData, gid, "aria2");
                    }
                    else
                    {
                        Console.WriteLine($"[BrowserHost] Aria2 AddDownload failed");
                        ForwardToGodot(jsonData, null, "aria2-failed");
                    }
                }
                else
                {
                    Console.WriteLine($"[BrowserHost] Aria2 not running, forwarding to Godot");
                    ForwardToGodot(jsonData, null, "no-aria2");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] NXM processing error: {ex.Message}");
                ForwardToGodot(jsonData, null, "error");
            }
        }

        private async Task<string?> _GetNexusDownloadLink(int modId, int fileId, string apiKey, long expires, long userId)
        {
            try
            {
                var httpClient = new System.Net.Http.HttpClient();
                httpClient.DefaultRequestHeaders.Add("Accept", "application/json");

                // ���� URL - ���ڷ� Premium �û���Ҫ key/expires/user_id ��������
                var url = $"https://api.nexusmods.com/v1/games/slaythespire2/mods/{modId}/files/{fileId}/download_link.json?key={apiKey}&expires={expires}&user_id={userId}";
                Console.WriteLine($"[BrowserHost] Calling Nexus API: {url}");

                var response = await httpClient.GetAsync(url);
                if (response.IsSuccessStatusCode)
                {
                    var json = await response.Content.ReadAsStringAsync();
                    var doc = System.Text.Json.JsonDocument.Parse(json);
                    if (doc.RootElement.ValueKind == System.Text.Json.JsonValueKind.Array &&
                        doc.RootElement.GetArrayLength() > 0)
                    {
                        return doc.RootElement[0].GetString();
                    }
                }
                else
                {
                    Console.WriteLine($"[BrowserHost] Nexus API error: {response.StatusCode}");
                    // ��ӡ��Ӧ�����Ա����
                    var errorContent = await response.Content.ReadAsStringAsync();
                    Console.WriteLine($"[BrowserHost] API response: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] Nexus API call failed: {ex.Message}");
            }
            return null;
        }

        private void ForwardToGodot(string jsonData, string? aria2Gid, string downloadType)
        {
            try
            {
                // ����� Aria2 GID���޸� JSON ���� aria2_gid
                string dataToSend = jsonData ?? "{}";
                if (!string.IsNullOrEmpty(aria2Gid))
                {
                    var doc = System.Text.Json.JsonDocument.Parse(jsonData ?? "{}");
                    var dict = new Dictionary<string, object>();
                    foreach (var prop in doc.RootElement.EnumerateObject())
                    {
                        dict[prop.Name] = prop.Value.ValueKind == System.Text.Json.JsonValueKind.String
                            ? prop.Value.GetString() ?? ""
                            : prop.Value.ToString();
                    }
                    dict["aria2_gid"] = aria2Gid;
                    dict["download_type"] = downloadType;
                    dataToSend = System.Text.Json.JsonSerializer.Serialize(dict);
                }

                var httpClient = new System.Net.Http.HttpClient();
                httpClient.Timeout = TimeSpan.FromSeconds(30);
                Program.CancelPendingRequests();

                var content = new StringContent(dataToSend, System.Text.Encoding.UTF8, "application/json");
                var response = httpClient.PostAsync($"http://localhost:{Program.GetCurrentPort()}/api/download", content).GetAwaiter().GetResult();

                if (response.IsSuccessStatusCode)
                {
                    Console.WriteLine($"[BrowserHost] Download request forwarded successfully (type: {downloadType})");
                }
                else
                {
                    Console.WriteLine($"[BrowserHost] Failed to forward download request: {response.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] ForwardToGodot error: {ex.Message}");
            }
        }
    }

    static class Program
    {
        // Store current port for external access
        private static int _staticPort = 28900;
        private static HttpListener? _httpListener;
        private static CancellationTokenSource? _httpListenerCts;
        private static Aria2Manager? _sharedAria2Manager;
        private static bool _httpListenerStarted = false;
        private static Microsoft.Web.WebView2.WinForms.WebView2? _webView;
        // ���� UI �̵߳� SynchronizationContext�����ڿ��̵߳���
        private static System.Threading.SynchronizationContext? _uiContext;

        public static Microsoft.Web.WebView2.WinForms.WebView2? WebView => _webView;
        public static void SetWebView(Microsoft.Web.WebView2.WinForms.WebView2? webView) => _webView = webView;
        public static void SetUiContext(System.Threading.SynchronizationContext? context) => _uiContext = context;

        public static int GetCurrentPort() => _staticPort;
        public static void SetCurrentPort(int port) => _staticPort = port;

        // ���ù����� Aria2Manager ����
        public static void SetAria2Manager(Aria2Manager manager)
        {
            _sharedAria2Manager = manager;
        }

        // ���� HTTP ����������ֹ�ظ�������
        public static void StartHttpListener(int port)
        {
            if (_httpListenerStarted) return;
            _httpListenerStarted = true;
            _httpListenerCts = new CancellationTokenSource();
            Task.Run(() => HttpListenerLoop(port, _httpListenerCts.Token));
        }

        private static async Task HttpListenerLoop(int port, CancellationToken ct)
        {
            Console.WriteLine($"[Program] Starting HTTP listener on port {port}");
            _httpListener = new HttpListener();
            // ͬʱ���� localhost �� 127.0.0.1����Ϊ Godot ����������֮һ
            _httpListener.Prefixes.Add($"http://localhost:{port}/");
            _httpListener.Prefixes.Add($"http://127.0.0.1:{port}/");
            Console.WriteLine($"[Program] HttpListener prefix registered: http://localhost:{port}/ and http://127.0.0.1:{port}/");
            try
            {
                _httpListener.Start();
                Console.WriteLine($"[Program] HTTP listener started on port {port}");

                while (!ct.IsCancellationRequested)
                {
                    try
                    {
                        var context = await _httpListener.GetContextAsync();
                        _ = Task.Run(() => HandleHttpRequest(context));
                    }
                    catch (HttpListenerException hex)
                    {
                        Console.WriteLine($"[Program] HttpListenerException: {hex.Message}, ErrorCode: {hex.ErrorCode}");
                        break;
                    }
                    catch (ObjectDisposedException) { break; }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Program] HTTP listener error: {ex.GetType().Name}: {ex.Message}");
                Console.WriteLine($"[Program] Inner: {ex.InnerException?.Message}");
            }
        }

        public static void ExecuteOnUIThread(Action action)
        {
            if (_webView != null)
            {
                if (_webView.InvokeRequired)
                {
                    _webView.Invoke(action);
                }
                else
                {
                    action();
                }
            }
        }

        public static async Task ExecuteOnUIThreadAsync(Func<Task> action)
        {
            if (_webView != null)
            {
                if (_webView.InvokeRequired)
                {
                    var tcs = new TaskCompletionSource<bool>();
                    _webView.Invoke(new Action(async () =>
                    {
                        try
                        {
                            await action();
                            tcs.SetResult(true);
                        }
                        catch (Exception ex)
                        {
                            tcs.SetException(ex);
                        }
                    }));
                    await tcs.Task;
                }
                else
                {
                    await action();
                }
            }
        }
        private static async Task HandleHttpRequest(HttpListenerContext context)
        {
            try
            {
                var path = context.Request.Url?.AbsolutePath ?? "";
                Console.WriteLine($"[Program] HTTP request: {context.Request.HttpMethod} {path}");

                if (path == "/aria2-download" && context.Request.HttpMethod == "POST")
                {
                    HandleAria2Download(context);
                }
                else if (path == "/aria2-progress" && context.Request.HttpMethod == "GET")
                {
                    HandleAria2Progress(context);
                }
                else if (path == "/download-complete" && context.Request.HttpMethod == "POST")
                {
                    HandleDownloadComplete(context);
                }
                else if (path == "/install-complete" && context.Request.HttpMethod == "POST")
                {
                    HandleInstallComplete(context);
                }
                else if (path == "/dpi-scale" && context.Request.HttpMethod == "POST")
                {
                    // ���� Godot �� dpi_scale ��Ӧ�õ� WebUI
                    try
                    {
                        using var reader = new StreamReader(context.Request.InputStream);
                        var body = await reader.ReadToEndAsync();
                        var json = System.Text.Json.JsonDocument.Parse(body);
                        if (json.RootElement.TryGetProperty("scale", out var scaleElement))
                        {
                            var scale = scaleElement.GetDouble();
                            Program.SetDpiScale(scale);
                            Console.WriteLine($"[BrowserHost] /dpi-scale: set scale to {scale}");
                        }
                        context.Response.StatusCode = 200;
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[BrowserHost] /dpi-scale error: {ex.Message}");
                        context.Response.StatusCode = 500;
                    }
                }
                else if (path == "/api/downloads/clear_history" && context.Request.HttpMethod == "POST")
                {
                    HandleClearDownloadHistory(context);
                }
                else if (path.StartsWith("/api/settings/") || path == "/api/settings")
                {
                    // API ���� - ת���� Godot LocalServer��֧�� GET �� POST��
                    ForwardToGodot(context);
                }
                else if (path.StartsWith("/css/") || path.StartsWith("/js/") || path.StartsWith("/assets/") || path.StartsWith("/locales") || path.StartsWith("/mock-") || path == "/icon.svg" || path == "/variables.css" || path == "/index.html")
                {
                    // ��̬�ļ����� - ת���� Godot LocalServer
                    ForwardToGodotStaticFile(context);
                }
                else if (path == "/api/health")
                {
                    context.Response.StatusCode = 200;
                    context.Response.ContentType = "application/json";
                    var buffer = Encoding.UTF8.GetBytes("{\"status\":\"ok\"}");
                    context.Response.OutputStream.Write(buffer);
                }
                else if (path.StartsWith("/api/"))
                {
                    // API ���� - ת���� Godot LocalServer��֧������ HTTP ������
                    ForwardToGodot(context);
                }
                else
                {
                    context.Response.StatusCode = 404;
                }
                context.Response.Close();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Program] HandleHttpRequest error: {ex.Message}");
            }
        }

        private static void HandleAria2Download(HttpListenerContext context)
        {
            try
            {
                using var reader = new StreamReader(context.Request.InputStream);
                var body = reader.ReadToEnd();
                Console.WriteLine($"[Program] Aria2 download request: {body}");
                Console.WriteLine($"[Program] Body length: {body.Length}, empty: {string.IsNullOrEmpty(body)}");

                if (string.IsNullOrWhiteSpace(body))
                {
                    Console.WriteLine("[Program] ERROR: Empty request body!");
                    context.Response.StatusCode = 400;
                    var buffer = Encoding.UTF8.GetBytes("{\"error\":\"Empty request body\"}");
                    context.Response.ContentType = "application/json";
                    context.Response.OutputStream.Write(buffer);
                    return;
                }

                var doc = System.Text.Json.JsonDocument.Parse(body);
                var url = "";
                var savePath = "";

                if (doc.RootElement.TryGetProperty("url", out var urlProp))
                    url = urlProp.GetString() ?? "";
                if (doc.RootElement.TryGetProperty("save_path", out var pathProp))
                    savePath = pathProp.GetString() ?? "";

                Console.WriteLine($"[Program] Parsed - url: {(string.IsNullOrEmpty(url) ? "EMPTY" : url.Substring(0, Math.Min(50, url.Length)) + "...")}, save_path: {savePath}");

                if (string.IsNullOrEmpty(url) || string.IsNullOrEmpty(savePath))
                {
                    context.Response.StatusCode = 400;
                    var buffer = Encoding.UTF8.GetBytes("{\"error\":\"url and save_path required\"}");
                    context.Response.ContentType = "application/json";
                    context.Response.OutputStream.Write(buffer);
                    return;
                }

                // ���� Aria2 ����
                if (_sharedAria2Manager != null && _sharedAria2Manager.IsRunning)
                {
                    var options = new Dictionary<string, string>
                    {
                        { "out", Path.GetFileName(savePath) },
                        { "dir", Path.GetDirectoryName(savePath) ?? "." }
                    };

                    var gid = _sharedAria2Manager.AddDownloadAsync(url, savePath, options).GetAwaiter().GetResult();
                    Console.WriteLine($"[Program] Aria2 download started: {gid}");

                    context.Response.StatusCode = 200;
                    context.Response.ContentType = "application/json";
                    var response = System.Text.Json.JsonSerializer.Serialize(new { success = true, gid = gid });
                    var buffer = Encoding.UTF8.GetBytes(response);
                    context.Response.OutputStream.Write(buffer);
                }
                else
                {
                    context.Response.StatusCode = 500;
                    var buffer = Encoding.UTF8.GetBytes("{\"error\":\"Aria2 not running\"}");
                    context.Response.ContentType = "application/json";
                    context.Response.OutputStream.Write(buffer);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Program] HandleAria2Download error: {ex.Message}");
                context.Response.StatusCode = 500;
            }
        }

        private static void HandleAria2Progress(HttpListenerContext context)
        {
            try
            {
                // ��ȡ GID ����
                var gid = context.Request.QueryString["gid"] ?? "";

                if (string.IsNullOrEmpty(gid))
                {
                    context.Response.StatusCode = 400;
                    var buffer = Encoding.UTF8.GetBytes("{\"error\":\"gid required\"}");
                    context.Response.ContentType = "application/json";
                    context.Response.OutputStream.Write(buffer);
                    return;
                }

                if (_sharedAria2Manager == null || !_sharedAria2Manager.IsRunning)
                {
                    context.Response.StatusCode = 500;
                    var buffer = Encoding.UTF8.GetBytes("{\"error\":\"Aria2 not running\"}");
                    context.Response.ContentType = "application/json";
                    context.Response.OutputStream.Write(buffer);
                    return;
                }

                // ��ȡ����״̬
                var status = _sharedAria2Manager.GetStatusAsync(gid).GetAwaiter().GetResult();
                Console.WriteLine($"[Program] HandleAria2Progress: gid={gid}, status={(status != null ? status.Status : "null")}, total={status?.TotalLength}, completed={status?.CompletedLength}");

                if (status == null)
                {
                    // status == null ��ʾ GID �� Aria2 �в����ڣ����� Aria2 ����������ʧ��
                    // ���� not_found ״̬���� Godot ��֪����Ҫ���¿�ʼ����
                    context.Response.StatusCode = 200;
                    context.Response.ContentType = "application/json";
                    var buffer = Encoding.UTF8.GetBytes("{\"gid\":\"" + gid + "\",\"completed\":false,\"status\":\"not_found\",\"error\":\"GID not found in Aria2, may need to restart download\"}");
                    context.Response.OutputStream.Write(buffer);
                    return;
                }

                context.Response.StatusCode = 200;
                context.Response.ContentType = "application/json";
                var response = System.Text.Json.JsonSerializer.Serialize(new
                {
                    gid = gid,
                    totalLength = status.TotalLength,
                    completedLength = status.CompletedLength,
                    downloadSpeed = status.Speed,
                    status = status.Status,
                    errorCode = status.ErrorCode,
                    errorMessage = status.ErrorMessage,
                    completed = status.Status == "complete"
                });
                var respBuffer = Encoding.UTF8.GetBytes(response);
                context.Response.OutputStream.Write(respBuffer);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Program] HandleAria2Progress error: {ex.Message}");
                context.Response.StatusCode = 500;
            }
        }

        private static void HandleDownloadComplete(HttpListenerContext context)
        {
            try
            {
                using var reader = new StreamReader(context.Request.InputStream);
                var body = reader.ReadToEnd();
                Console.WriteLine($"[Program] Download complete notification: {body}");

                // ��ȡ WebView ���ã��� HTTP �߳��ϣ�
                var webViewRef = _webView;
                if (webViewRef != null)
                {
                    Console.WriteLine("[Program] Download WebView available, dispatching via BeginInvoke...");

                    // ׼���ű����ݣ��� HTTP �߳���ִ��ת�壩
                    var bodyJson = Uri.EscapeDataString(body);
                    var script = $@"
                        (function() {{
                            try {{
                                var bodyStr = decodeURIComponent('{bodyJson}');
                                var data = JSON.parse(bodyStr);
                                window.dispatchEvent(new CustomEvent('sts2-download-complete', {{
                                    detail: {{ id: data.id || '', mod_name: data.mod_name || '', status: data.status || '' }}
                                }}));
                                console.log('[BrowserHost] Download complete event dispatched:', data.mod_name);
                            }} catch(e) {{
                                console.error('[BrowserHost] Download complete parse error:', e.message);
                            }}
                        }})();
                    ";

                    // ʹ�� BeginInvoke �� UI �߳���ִ�нű�
                    // BeginInvoke �Ὣ�ص��Ŷӵ� UI �̣߳���������ִ��
                    webViewRef.BeginInvoke(new Action(() =>
                    {
                        try
                        {
                            // �� UI �߳��Ϸ��� CoreWebView2
                            var coreWebView2 = webViewRef.CoreWebView2;
                            if (coreWebView2 == null)
                            {
                                Console.WriteLine("[Program] Download: CoreWebView2 is null!");
                                return;
                            }
                            Console.WriteLine("[Program] Download: CoreWebView2 accessed successfully on UI thread");
                            coreWebView2.ExecuteScriptAsync(script);
                            Console.WriteLine("[Program] Download script executed via BeginInvoke");
                        }
                        catch (Exception innerEx)
                        {
                            Console.WriteLine($"[Program] Download UI thread error: {innerEx.Message}");
                        }
                    }));
                }

                context.Response.StatusCode = 200;
                context.Response.ContentType = "application/json";
                var buffer = Encoding.UTF8.GetBytes("{\"success\":true}");
                context.Response.OutputStream.Write(buffer);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Program] HandleDownloadComplete error: {ex.Message}");
                context.Response.StatusCode = 500;
            }
        }

        private static void HandleInstallComplete(HttpListenerContext context)
        {
            try
            {
                using var reader = new StreamReader(context.Request.InputStream);
                var body = reader.ReadToEnd();
                Console.WriteLine($"[Program] Install complete notification: {body}");

                // ֪ͨ WebView2 JavaScript������� UI �̵߳��ã�
                // �Ȼ�ȡ WebView �ı�������
                var webViewRef = _webView;
                var uiContext = _uiContext;
                if (webViewRef != null)
                {
                    Console.WriteLine("[Program] WebView available, dispatching event...");

                    // ׼���ű����ݣ������߳���ִ��ת�壩
                    var bodyJson = Uri.EscapeDataString(body);
                    var script = $@"
                        (function() {{
                            try {{
                                var bodyStr = decodeURIComponent('{bodyJson}');
                                var data = JSON.parse(bodyStr);
                                window.dispatchEvent(new CustomEvent('sts2-install-complete', {{
                                    detail: {{ id: data.id || '', mod_name: data.mod_name || '', status: data.status || '' }}
                                }}));
                                console.log('[BrowserHost] Install complete event dispatched:', data.mod_name);
                            }} catch(e) {{
                                console.error('[BrowserHost] Install complete parse error:', e.message);
                            }}
                        }})();
                    ";

                    // ʹ�� BeginInvoke �� UI �߳���ִ�нű�
                    webViewRef.BeginInvoke(new Action(() =>
                    {
                        try
                        {
                            // �� UI �߳���ֱ�ӷ��� CoreWebView2
                            // BeginInvoke �ص��� UI �߳������У���ʱ CoreWebView2 Ӧ�ÿ���
                            if (webViewRef.CoreWebView2 == null)
                            {
                                Console.WriteLine("[Program] Install: CoreWebView2 is null!");
                                return;
                            }
                            Console.WriteLine("[Program] Install: CoreWebView2 accessed successfully on UI thread");
                            webViewRef.CoreWebView2.ExecuteScriptAsync(script);
                            Console.WriteLine("[Program] Script executed via BeginInvoke");
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"[Program] Install UI thread error: {ex.Message}");
                        }
                    }));
                }
                else
                {
                    Console.WriteLine("[Program] ERROR: WebView not available!");
                }

                context.Response.StatusCode = 200;
                context.Response.ContentType = "application/json";
                var buffer = Encoding.UTF8.GetBytes("{\"success\":true}");
                context.Response.OutputStream.Write(buffer);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Program] HandleInstallComplete error: {ex.Message}");
                context.Response.StatusCode = 500;
            }
        }

        // ���������ʷ��WebUI -> Godot��
        private static void HandleClearDownloadHistory(HttpListenerContext context)
        {
            try
            {
                // ��ȡ WebUI ���͵������壨���ܰ��� include_files ������
                string requestBody = "";
                using (var reader = new StreamReader(context.Request.InputStream))
                {
                    requestBody = reader.ReadToEnd();
                }

                Console.WriteLine($"[Program] HandleClearDownloadHistory: requestBody={requestBody}");

                // ת���� Godot ����
                var httpClient = new System.Net.Http.HttpClient();
                httpClient.Timeout = TimeSpan.FromSeconds(10);

                var content = new StringContent(requestBody, System.Text.Encoding.UTF8, "application/json");
                var response = httpClient.PostAsync($"http://localhost:{Program.GetCurrentPort()}/api/downloads/clear_history", content).GetAwaiter().GetResult();

                if (response.IsSuccessStatusCode)
                {
                    context.Response.StatusCode = 200;
                    context.Response.ContentType = "application/json";
                    var buffer = Encoding.UTF8.GetBytes("{\"success\":true}");
                    context.Response.OutputStream.Write(buffer);

                    // ��ճɹ���֪ͨ WebUI ������ʷҲ�����
                    // �������Է�ֹ WebUI ���յ���Ӧǰ���յ���һ�ֵ���ѯ����
                    NotifyWebUIClearHistoryComplete();
                }
                else
                {
                    Console.WriteLine($"[Program] HandleClearDownloadHistory: Godot returned {response.StatusCode}");
                    context.Response.StatusCode = (int)response.StatusCode;
                    var buffer = Encoding.UTF8.GetBytes("{\"error\":\"Failed to clear history\"}");
                    context.Response.ContentType = "application/json";
                    context.Response.OutputStream.Write(buffer);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Program] HandleClearDownloadHistory error: {ex.Message}");
                context.Response.StatusCode = 500;
            }
        }

        // ת������� Godot LocalServer��֧������ HTTP ������
        private static void ForwardToGodot(HttpListenerContext context)
        {
            try
            {
                var path = context.Request.Url?.AbsolutePath ?? "";
                var godotPort = Program.GetCurrentPort();
                var url = $"http://localhost:{godotPort}{path}";

                Console.WriteLine($"[Program] Forwarding to Godot: {context.Request.HttpMethod} {url}");

                var httpClient = new System.Net.Http.HttpClient();
                httpClient.Timeout = TimeSpan.FromSeconds(30);

                // �������󣬱���ԭʼ HTTP ����
                var request = new HttpRequestMessage(new HttpMethod(context.Request.HttpMethod), url);

                // ת������ͷ���ų� host��
                foreach (var key in context.Request.Headers.AllKeys)
                {
                    if (key != null)
                    {
                        var value = context.Request.Headers[key];
                        if (!string.IsNullOrEmpty(value) && key.ToLower() != "host")
                        {
                            try { request.Headers.TryAddWithoutValidation(key, value); } catch { }
                        }
                    }
                }

                // ת�������壨����� POST/PUT��
                if (context.Request.HttpMethod == "POST" || context.Request.HttpMethod == "PUT")
                {
                    using var reader = new StreamReader(context.Request.InputStream);
                    var body = reader.ReadToEnd();
                    if (!string.IsNullOrEmpty(body))
                    {
                        request.Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json");
                    }
                }

                var response = httpClient.SendAsync(request).GetAwaiter().GetResult();

                context.Response.StatusCode = (int)response.StatusCode;
                context.Response.ContentType = response.Content.Headers.ContentType?.MediaType ?? "application/json";

                var buffer = response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
                context.Response.OutputStream.Write(buffer, 0, buffer.Length);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Program] ForwardToGodot error: {ex.Message}");
                context.Response.StatusCode = 500;
            }
        }

        // ת����̬�ļ������ Godot LocalServer���� GET��
        private static void ForwardToGodotStaticFile(HttpListenerContext context)
        {
            try
            {
                var path = context.Request.Url?.AbsolutePath ?? "";
                var godotPort = Program.GetCurrentPort();
                var url = $"http://localhost:{godotPort}{path}";

                Console.WriteLine($"[Program] Forwarding static file request to Godot: {url}");

                var httpClient = new System.Net.Http.HttpClient();
                httpClient.Timeout = TimeSpan.FromSeconds(10);

                // ת������ Godot
                var request = new HttpRequestMessage(HttpMethod.Get, url);
                foreach (var key in context.Request.Headers.AllKeys)
                {
                    if (key != null)
                    {
                        var value = context.Request.Headers[key];
                        if (!string.IsNullOrEmpty(value) && key.ToLower() != "host")
                        {
                            try { request.Headers.TryAddWithoutValidation(key, value); } catch { }
                        }
                    }
                }

                var response = httpClient.SendAsync(request).GetAwaiter().GetResult();

                context.Response.StatusCode = (int)response.StatusCode;
                context.Response.ContentType = response.Content.Headers.ContentType?.MediaType ?? "text/plain";

                var buffer = response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
                context.Response.OutputStream.Write(buffer, 0, buffer.Length);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Program] ForwardToGodotStaticFile error: {ex.Message}");
                context.Response.StatusCode = 500;
            }
        }

        // ֪ͨ WebUI ��ʷ�����ɣ�������ֹ��ѯ���������ʷ��
        private static void NotifyWebUIClearHistoryComplete()
        {
            var webView = _webView;
            if (webView == null) return;

            webView.BeginInvoke(new Action(() =>
            {
                try
                {
                    var webViewRef = webView;
                    if (webViewRef?.CoreWebView2 == null)
                    {
                        Console.WriteLine("[Program] NotifyWebUIClearHistoryComplete: CoreWebView2 not available");
                        return;
                    }

                    // ����һ���¼���֪ͨ downloads.js ���� _localHistoryCleared = true
                    var script = @"
                        (function() {
                            if (window.STS2Downloads) {
                                window.STS2Downloads._localHistoryCleared = true;
                                console.log('[Program] STS2Downloads._localHistoryCleared set to true');
                            }
                        })()";
                    webViewRef.CoreWebView2.ExecuteScriptAsync(script);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Program] NotifyWebUIClearHistoryComplete error: {ex.Message}");
                }
            }));
        }

        // ֪ͨ WebUI ������ɣ���̬�������� Aria2 �¼��ص����ã�
        public static void NotifyWebUIOfDownloadComplete(string modName, string downloadId)
        {
            var webView = _webView;
            if (webView == null) return;

            webView.BeginInvoke(new Action(() =>
            {
                try
                {
                    var webViewRef = webView;
                    if (webViewRef?.CoreWebView2 == null)
                    {
                        Console.WriteLine("[Program] NotifyWebUIOfDownloadComplete: CoreWebView2 not available");
                        return;
                    }

                    var escapedName = modName.Replace("'", "\\'").Replace("\"", "\\\"").Replace("\n", " ").Replace("\r", "");
                    var escapedId = downloadId.Replace("'", "\\'").Replace("\"", "\\\"");
                    var body = System.Text.Json.JsonSerializer.Serialize(new { id = escapedId, mod_name = escapedName, status = "completed" });

                    var script = $@"
                        (function() {{
                            var data = {body};
                            window.dispatchEvent(new CustomEvent('sts2-download-complete', {{
                                detail: {{ id: data.id, mod_name: data.mod_name, status: data.status }}
                            }}));
                            console.log('[BrowserHost] Aria2 download complete notified to WebUI:', data.mod_name);
                        }})();
                    ";
                    _ = webViewRef.CoreWebView2.ExecuteScriptAsync(script);
                    Console.WriteLine($"[Program] NotifyWebUIOfDownloadComplete (UI Thread): {modName}, id={downloadId}");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Program] NotifyWebUIOfDownloadComplete error: {ex.Message}");
                }
            }));
        }

        // 通知 WebUI 安装完成（静态方法，�?Godot 调用�?
        public static void NotifyWebUIOfInstallComplete(string modName, string downloadId)
        {
            var webView = _webView;
            if (webView == null) return;

            webView.BeginInvoke(new Action(() =>
            {
                try
                {
                    var webViewRef = webView;
                    if (webViewRef?.CoreWebView2 == null)
                    {
                        Console.WriteLine("[Program] NotifyWebUIOfInstallComplete: CoreWebView2 not available");
                        return;
                    }

                    var escapedName = modName.Replace("'", "\\'").Replace("\"", "\\\"").Replace("\n", " ").Replace("\r", "");
                    var escapedId = downloadId.Replace("'", "\\'").Replace("\"", "\\\"");
                    var body = System.Text.Json.JsonSerializer.Serialize(new { id = escapedId, mod_name = escapedName, status = "install_complete" });

                    var script = $@"
                        (function() {{
                            var data = {body};
                            window.dispatchEvent(new CustomEvent('sts2-install-complete', {{
                                detail: {{ id: data.id, mod_name: data.mod_name, status: data.status }}
                            }}));
                            console.log('[BrowserHost] Mod install complete notified to WebUI:', data.mod_name);
                        }})();
                    ";
                    _ = webViewRef.CoreWebView2.ExecuteScriptAsync(script);
                    Console.WriteLine($"[Program] NotifyWebUIOfInstallComplete (UI Thread): {modName}, id={downloadId}");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Program] NotifyWebUIOfInstallComplete error: {ex.Message}");
                }
            }));
        }

        // ֪ͨ WebUI DPI ���ű仯����̬�������� HTTP �˵���ã�
        public static void SetDpiScale(double scale)
        {
            var webView = _webView;
            if (webView == null) return;

            webView.BeginInvoke(new Action(() =>
            {
                try
                {
                    var webViewRef = webView;
                    if (webViewRef?.CoreWebView2 == null)
                    {
                        Console.WriteLine("[Program] SetDpiScale: CoreWebView2 not available");
                        return;
                    }

                    var script = $@"
                        (function() {{
                            if (window.app && window.app.applyDpiScale) {{
                                window.app.applyDpiScale({scale});
                                console.log('[BrowserHost] DPI scale applied to WebUI: {scale}');
                            }}
                        }})();
                    ";
                    _ = webViewRef.CoreWebView2.ExecuteScriptAsync(script);
                    Console.WriteLine($"[Program] SetDpiScale (UI Thread): scale={scale}");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Program] SetDpiScale error: {ex.Message}");
                }
            }));
        }

        // Cancel pending requests to prevent thread pool starvation
        public static void CancelPendingRequests()
        {
            try
            {
                _pendingCts?.Cancel();
            }
            catch { }
            _pendingCts = new CancellationTokenSource();
        }

        // Job Object API
        private static CancellationTokenSource? _pendingCts;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr CreateJobObjectW(IntPtr lpJobAttributes, string lpName);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetJobObjectUnitLimit(IntPtr hJob, IntPtr lpJobObjectInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetCurrentProcess();

        // JobObjectBasicLimitInformation
        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public ulong Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

        [STAThread]
        static void Main(string[] args)
        {
            // ���� Job Object - ���ǹؼ���ȷ��������ֹʱ�Զ��������о��
            IntPtr jobHandle = CreateJobObjectW(IntPtr.Zero, null);
            if (jobHandle != IntPtr.Zero)
            {
                // ���� Job ���ƣ�������ľ���ر�ʱ�Զ���ֹ����
                var limitInfo = new JOBOBJECT_BASIC_LIMIT_INFORMATION();
                limitInfo.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

                // ����ǰ���̼��� Job Object
                IntPtr currentProcess = GetCurrentProcess();
                bool assigned = AssignProcessToJobObject(jobHandle, currentProcess);
                Console.WriteLine($"[BrowserHost] Job Object ����: {assigned}");

                // ע�⣺����Ҫ�ֶ� CloseHandle(jobHandle)�������˳�ʱϵͳ���Զ�����
            }

            IntPtr parentHwnd = IntPtr.Zero;
            int initialWidth = 1280;
            int initialHeight = 720;
            int initialPort = 28900;  // Ĭ�϶˿�

            // �������в�����ȡ�����ھ���ͳ�ʼ�ߴ�
            if (args.Length >= 1 && long.TryParse(args[0], out var parsedHwnd))
            {
                parentHwnd = new IntPtr(parsedHwnd);
                Console.WriteLine($"[BrowserHost] �����ھ��: {parentHwnd}");
            }

            if (args.Length >= 4)
            {
                if (int.TryParse(args[1], out var w))
                    initialWidth = w;
                if (int.TryParse(args[2], out var h))
                    initialHeight = h;
                if (int.TryParse(args[3], out var p))
                    initialPort = p;
                Console.WriteLine($"[BrowserHost] ��ʼ�ߴ�: {initialWidth}x{initialHeight}, �˿�: {initialPort}");
            }
            else if (args.Length >= 3)
            {
                if (int.TryParse(args[1], out var w))
                    initialWidth = w;
                if (int.TryParse(args[2], out var h))
                    initialHeight = h;
                Console.WriteLine($"[BrowserHost] ��ʼ�ߴ�: {initialWidth}x{initialHeight}");
            }

            // ���� WebView2 ����
            var browser = new BrowserHost(parentHwnd, initialWidth, initialHeight);

            Application.Run();
        }
    }

    class BrowserHost : ApplicationContext
    {
        private static string _debugLogPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "BrowserHost_debug.log");

        private static void DebugLog(string msg)
        {
            try
            {
                var logMsg = $"[{DateTime.Now:HH:mm:ss.fff}] {msg}";
                Console.WriteLine($"[DEBUG] {logMsg}");
                File.AppendAllText(_debugLogPath, logMsg + "\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DEBUG ERROR] {ex.Message}");
            }
        }

        private static Microsoft.Web.WebView2.WinForms.WebView2? _webView;

        // Static accessor for WebView (used by static handlers) - moved to Program class
        private readonly int _defaultPort;
        private readonly int[] _backupPorts = { 28901, 28902, 28903, 28904 };
        private int _currentPort;
        private int _retryCount = 0;
        private readonly IntPtr _parentHwnd;
        private Form? _container;
        private System.Windows.Forms.Timer? _resizeTimer;
        private int _lastParentWidth = 0;
        private int _lastParentHeight = 0;
        private ToggleButton? _toggleBtn;
        private bool _isDrawerOpen = false;
        private ContextMenuStrip? _drawerMenu;
        private Panel? _drawerPanel;
        private UpdateDialogPanel? _updateDialogPanel;
        private bool _isAnimating = false;
        private System.Windows.Forms.Timer? _hoverTimer;
        private bool _isHovering = false;
        private System.Windows.Forms.Timer? _mouseCheckTimer;
        private System.Drawing.Point _lastMousePos;
        private const int DRAWER_WIDTH = 260;
        private const int TOGGLE_WIDTH_EXPANDED = 44;   // չ������������
        private const int TOGGLE_WIDTH_COLLAPSED = 12;  // ��̬¶��12px�ڱ�Ե
        private const int TOGGLE_HEIGHT = 44;
        private const int ANIM_STEPS = 10;
        private const int ANIM_INTERVAL = 15;

        // Win32 API
        [DllImport("user32.dll")]
        private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

        [DllImport("user32.dll")]
        private static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        private static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        private static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool SetMenu(IntPtr hWnd, IntPtr hMenu);

        [DllImport("user32.dll")]
        private static extern IntPtr CreatePopupMenu();

        [DllImport("user32.dll")]
        private static extern bool AppendMenu(IntPtr hMenu, uint uFlags, uint uIDNewItem, string lpNewItem);

        [DllImport("user32.dll")]
        private static extern int TrackPopupMenu(IntPtr hMenu, uint uFlags, int x, int y, int nReserved, IntPtr hWnd, IntPtr prcRect);

        private const uint SWP_NOACTIVATE = 0x0004;
        private const uint SWP_NOZORDER = 0x0004;
        private const uint SWP_SHOWWINDOW = 0x0040;
        private const int SW_SHOW = 5;

        private const uint WM_COMMAND = 0x0111;
        private const int ID_CONFIG = 1001;
        private const int ID_LAUNCH_VANILLA = 1002;
        private const int ID_LAUNCH_MODDED = 1003;
        private const int ID_EXIT = 1004;

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        public BrowserHost(IntPtr parentHwnd, int initialWidth, int initialHeight, int defaultPort = 18765)
        {
            _parentHwnd = parentHwnd;
            _defaultPort = defaultPort;
            _currentPort = defaultPort;

            _currentPort = _readPortFromFile();

            Console.WriteLine("[BrowserHost] ������������");
            _container = new Form();
            _container.FormBorderStyle = FormBorderStyle.None;
            _container.Text = "BrowserHost";
            _container.ShowInTaskbar = false;
            _container.StartPosition = FormStartPosition.Manual;
            _container.Width = initialWidth;
            _container.Height = initialHeight;
            _container.TopLevel = false;
            _container.Opacity = 1.0;
            _container.Padding = new Padding(0);
            _container.Margin = new Padding(0);
            _container.AutoScaleMode = AutoScaleMode.Dpi;
            _container.Closing += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] �������ڹر�");
            };

            InitializeAsync();
        }

        public int _readPortFromFile()
        {
            var portFilePath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Godot", "app_userdata", "sts-2-modmanager", ".local_server_port");

            if (File.Exists(portFilePath))
            {
                try
                {
                    var content = File.ReadAllText(portFilePath).Trim();
                    if (int.TryParse(content, out int port))
                    {
                        Console.WriteLine($"[BrowserHost] ���ļ���ȡ�˿�: {port}");
                        return port;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[BrowserHost] ��ȡ�˿��ļ�ʧ��: {ex.Message}");
                }
            }

            var altPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Godot", "app_userdata", "sts-2-modmanager", ".local_server_port");
            if (File.Exists(altPath))
            {
                try
                {
                    var content = File.ReadAllText(altPath).Trim();
                    if (int.TryParse(content, out int port))
                    {
                        Console.WriteLine($"[BrowserHost] �ӱ���·����ȡ�˿�: {port}");
                        return port;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[BrowserHost] ��ȡ���ö˿��ļ�ʧ��: {ex.Message}");
                }
            }

            Console.WriteLine($"[BrowserHost] ʹ��Ĭ�϶˿�: {_defaultPort}");
            return _defaultPort;
        }

        public void _updatePort(int newPort)
        {
            _currentPort = newPort;
            Program.SetCurrentPort(newPort);
            if (_webView != null && _webView.CoreWebView2 != null)
            {
                _webView.CoreWebView2.Navigate($"http://localhost:{_currentPort}/index.html");
            }
        }

        // ���ʵ�ʿ��õĶ˿�
        private async Task<int> _detectAvailablePortAsync()
        {
            // ���ȶ�ȡ�˿��ļ�
            var filePort = _readPortFromFile();
            var portsToTry = new List<int> { filePort };
            portsToTry.AddRange(_backupPorts);

            foreach (var port in portsToTry)
            {
                try
                {
                    using var client = new System.Net.Http.HttpClient();
                    // ���ӳ�ʱʱ�䵽 5 �룬�� Godot ������Ӧʱ��
                    client.Timeout = TimeSpan.FromSeconds(5);
                    var response = await client.GetAsync($"http://localhost:{port}/api/health");
                    if (response.IsSuccessStatusCode)
                    {
                        Console.WriteLine($"[BrowserHost] �˿� {port} ����");
                        return port;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[BrowserHost] �˿� {port} ������: {ex.Message}");
                }
            }

            // ����������ã������ļ��еĶ˿���ΪĬ��ֵ
            Console.WriteLine($"[BrowserHost] û�м�⵽���ö˿ڣ�ʹ��Ĭ��ֵ: {filePort}");
            return filePort;
        }

        // ����ʱ���ƵĶ˿ڼ�⣨���ڵ������������ⳤʱ��ȴ���
        // ���ԣ�ֱ��ʹ���ļ��еĶ˿ڣ��������м��
        // ��Ϊ LocalServer һ�������ͻᱣ�����У��˿ڲ����
        private Task<int> _detectAvailablePortWithTimeoutAsync()
        {
            var filePort = _readPortFromFile();
            Console.WriteLine($"[BrowserHost] ʹ�ö˿�: {filePort}");
            return Task.FromResult(filePort);
        }

        private async void InitializeAsync()
        {
            try
            {
                Console.WriteLine("[BrowserHost] ��ʼ��ʼ�� WebView2");

                var userDataFolder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "STS2ModManager", "WebView2");

                Directory.CreateDirectory(userDataFolder);

                Console.WriteLine($"[BrowserHost] �û�����Ŀ¼: {userDataFolder}");

                var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                Console.WriteLine("[BrowserHost] ���������ɹ�");

                _webView = new Microsoft.Web.WebView2.WinForms.WebView2();
                _webView.Dock = DockStyle.Fill;

                // Register WebView with Program class for static handlers
                Program.SetWebView(_webView);
                // ���� UI �̵߳� SynchronizationContext
                Program.SetUiContext(System.Threading.SynchronizationContext.Current);

                _container!.Controls.Add(_webView);
                _container!.FormBorderStyle = FormBorderStyle.None;
                _container!.WindowState = FormWindowState.Normal;
                _container!.BackColor = System.Drawing.Color.FromArgb(20, 20, 20);

                await Task.Delay(200);

                await _webView.EnsureCoreWebView2Async(env);
                Console.WriteLine("[BrowserHost] CoreWebView2 ��ʼ���ɹ�");

                _webView.CoreWebView2.Settings.AreDevToolsEnabled = true;
                _webView.CoreWebView2.Settings.IsScriptEnabled = true;
                _webView.CoreWebView2.Settings.IsWebMessageEnabled = true;
                _webView.CoreWebView2.Settings.IsStatusBarEnabled = false;

                // ע�⣺AddHostObjectToScript ������ Navigate ֮ǰ���ã�������ҳ����غ�
                // ������ NavigationCompleted ��ע�ᣨ���·���

                _webView.NavigationStarting += (s, e) =>
                {
                    Console.WriteLine($"[BrowserHost] ������ʼ: {e.Uri}");

                    // ȡ���κι�������󣬷�ֹ�̳߳ؼ���
                    Program.CancelPendingRequests();

                    // Track current port for download requests
                    if (e.Uri.StartsWith("http://localhost:"))
                    {
                        try
                        {
                            var uri = new Uri(e.Uri);
                            Program.SetCurrentPort(uri.Port);
                        }
                        catch { }
                    }
                };

                _webView.NavigationCompleted += async (s, e) =>
                {
                    var currentUrl = _webView.CoreWebView2?.Source ?? "";
                    Console.WriteLine($"[BrowserHost] �������: �ɹ�={e.IsSuccess}, HTTP={e.HttpStatusCode}, URL={currentUrl}");

                    // ����� Nexus Mods ҳ�棬���ܳɹ�ʧ�ܶ������б�������
                    if (currentUrl.Contains("nexusmods.com"))
                    {
                        if (!e.IsSuccess)
                        {
                            Console.WriteLine($"[BrowserHost] Nexus ҳ�����ʧ��: {e.WebErrorStatus}");
                            // ��ִ���κ����ԣ����ִ���ҳ����ʾ
                        }
                        return; // ��������ҳ��� HostObject ע���߼�
                    }

                    if (!e.IsSuccess)
                    {
                        Console.WriteLine($"[BrowserHost] ����: {e.WebErrorStatus}");
                        // ֻ���״�ʧ��ʱ����һ��
                        if (_retryCount == 0)
                        {
                            _retryCount = 1;
                            // ����ʱʹ�� hash URL���� WebUI ��ȷ�л���ģ��ҳ
                            var retryUrl = $"http://localhost:{_currentPort}/index.html#mods";
                            Console.WriteLine($"[BrowserHost] ���Ե�����: {retryUrl}");
                            // ����ǰȡ�����й�������
                            Program.CancelPendingRequests();
                            Thread.Sleep(300);
                            _webView.CoreWebView2.Navigate(retryUrl);
                        }
                        else
                        {
                            Console.WriteLine($"[BrowserHost] ����Ҳʧ�ܣ�����");
                            // ������ʾ MessageBox���������� UI
                            // �û�����ͨ������˵��ķ�����ҳ��ť����
                        }
                    }
                    else
                    {
                        Console.WriteLine($"[BrowserHost] �ɹ����ӵ��˿� {_currentPort}");
                        // ���� BrowserHostObject �����ø��µ����ص�
                        var browserHostObj = new BrowserHostObject();
                        browserHostObj.aria2Manager = new Aria2Manager();

                        // �������� Aria2��ȷ��ҳ�����ǰ�Ѿ���
                        // ʹ�����·������ BrowserHost.exe ͬĿ¼��
                        string aria2Path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "aria2c.exe");
                        Console.WriteLine($"[BrowserHost] Aria2 path: {aria2Path}");
                        Console.WriteLine($"[BrowserHost] Aria2 exists: {File.Exists(aria2Path)}");
                        var aria2Started = browserHostObj.aria2Manager.Start(aria2Path);
                        Console.WriteLine($"[BrowserHost] Aria2 started: {aria2Started}");

                        // ���ù��� Aria2Manager ������ HTTP ������
                        // ʹ�ù̶��˿� 18765 ��Ϊ Aria2 HTTP API �˿�
                        Program.SetAria2Manager(browserHostObj.aria2Manager);
                        Console.WriteLine($"[BrowserHost] Shared Aria2Manager set, IsRunning: {browserHostObj.aria2Manager.IsRunning}");

                        // ���� Aria2 ��������¼�������֪ͨ WebUI��
                        browserHostObj.aria2Manager.DownloadComplete += (sender, dl) => {
                            Console.WriteLine($"[BrowserHost] Aria2 download complete: GID={dl.Gid}, path={dl.SavePath}");
                            // ������·����ȡ�ļ�����Ϊ mod_name
                            var modName = Path.GetFileNameWithoutExtension(dl.SavePath);
                            // �ӻ���ķ������ݻ�ȡ download_id��ͨ�� GID ƥ�䣩
                            // ����ֱ��ʹ���ļ�����Ϊ��ʶ
                            var downloadId = $"aria2_{dl.Gid}";
                            Program.NotifyWebUIOfDownloadComplete(modName, downloadId);
                        };

                        // �������ؽ����¼������ڸ��� WebUI��
                        browserHostObj.aria2Manager.ProgressChanged += (sender, progressData) => {
                            var (gid, progress, speed) = progressData;
                            // ���ȸ��¿���ͨ����ѯ���ƴ��ݵ� WebUI
                            // Ŀǰ��ʱ��ʵ��ʵʱ�������ͣ�WebUI ͨ�� /api/downloads ��ѯ��ȡ��Ծ����
                            // Console.WriteLine($"[BrowserHost] Aria2 progress: GID={gid}, {progress}%, {speed} bytes/s");
                        };

                        Program.StartHttpListener(18765);
                        Console.WriteLine($"[BrowserHost] Aria2 HTTP API listening on port 18765");

                        // aria2Manager.CleanupOrphanProcesses() will be called here if needed
                        browserHostObj.SetUpdateDialogCallback((currentVer, newVer, changelog, downloadUrl) =>
                        {
                            Console.WriteLine($"[BrowserHost] ��ʾ���µ���: {currentVer} -> {newVer}");
                            ShowUpdateDialog(currentVer, newVer, changelog, downloadUrl);
                        });

                        // ���õ����ص�
                        browserHostObj.SetNavigateCallback((url) =>
                        {
                            Console.WriteLine($"[BrowserHost] Navigate callback: {url}");
                            if (_webView?.CoreWebView2 != null)
                            {
                                _webView.CoreWebView2.Navigate(url);
                            }
                        });

                        // �����ɹ���ע�� Host Object��������ҳ����غ�
                        try
                        {
                            // ���� WebView ���ã����� ExecuteScript��
                            browserHostObj._webView = _webView;
                            _webView.CoreWebView2.AddHostObjectToScript("browserHost", browserHostObj);
                            Console.WriteLine("[BrowserHost] AddHostObjectToScript ��ע��");
                        }
                        catch (Exception ex2)
                        {
                            Console.WriteLine($"[BrowserHost] AddHostObjectToScript ע��ʧ��: {ex2.Message}");
                            Console.WriteLine($"[BrowserHost] ex2 type: {ex2.GetType().FullName}");
                        }
                    }
                };

                _webView.CoreWebView2.NewWindowRequested += (s, e) =>
                {
                    Console.WriteLine($"[BrowserHost] �´�������: {e.Uri}");
                    e.Handled = true;
                    _webView?.CoreWebView2.Navigate(e.Uri);
                };

                // Inject extension script when navigating to Nexus Mods
                _webView.CoreWebView2.NavigationCompleted += async (s, e) =>
                {
                    if (!e.IsSuccess) return;

                    var currentUrl = _webView.CoreWebView2.Source;
                    if (string.IsNullOrEmpty(currentUrl) || !currentUrl.Contains("nexusmods.com"))
                        return;

                    Console.WriteLine($"[BrowserHost] Nexus page loaded, injecting extension...");
                    Console.WriteLine($"[BrowserHost] Current URL: {currentUrl}");

                    // �ȴ�ҳ����ȫ���أ�������̬���ݣ�
                    await Task.Delay(2000);

                    await InjectExtensionScriptAsync();
                };

                // ���� URL �仯��SPA ������
                string lastInjectedUrl = "";
                _webView.CoreWebView2.SourceChanged += async (s, e) =>
                {
                    var currentUrl = _webView.CoreWebView2.Source;
                    if (string.IsNullOrEmpty(currentUrl) || !currentUrl.Contains("nexusmods.com"))
                        return;

                    // �����ظ�ע��ͬһҳ��
                    if (currentUrl == lastInjectedUrl)
                        return;

                    Console.WriteLine($"[BrowserHost] Nexus URL changed to: {currentUrl}");
                    lastInjectedUrl = currentUrl;

                    // �ȴ�ҳ�����ݸ���
                    await Task.Delay(2000);

                    await InjectExtensionScriptAsync();
                };

                async Task InjectExtensionScriptAsync()
                {
                    try
                    {
                        // Read the extension script
                        var extensionPath = Path.Combine(
                            Path.GetDirectoryName(Application.ExecutablePath) ?? ".",
                            "extension", "nexus_inject.js");

                        if (!File.Exists(extensionPath))
                        {
                            extensionPath = Path.Combine(
                                Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".",
                                "extension", "nexus_inject.js");
                        }

                        Console.WriteLine($"[BrowserHost] Looking for extension script at: {extensionPath}");

                        if (File.Exists(extensionPath))
                        {
                            var scriptContent = await File.ReadAllTextAsync(extensionPath);
                            Console.WriteLine($"[BrowserHost] Extension script loaded, length: {scriptContent.Length}");

                            // Use ExecuteScriptAsync with the script content directly
                            // Wrap it in an IIFE to avoid conflicts
                            var wrappedScript = "(function(){" + scriptContent + "})();";
                            await _webView.CoreWebView2.ExecuteScriptAsync(wrappedScript);

                            Console.WriteLine($"[BrowserHost] Extension script injected into Nexus page");

                            // �ӳٺ���ű��Ƿ�ɹ�����
                            await Task.Delay(3000);
                            var consoleCheck = await _webView.CoreWebView2.ExecuteScriptAsync(
                                "(function(){ return !!window.STS2_EXTENSION_LOADED; })()"
                            );
                            Console.WriteLine($"[BrowserHost] Extension loaded check: {consoleCheck}");
                        }
                        else
                        {
                            Console.WriteLine($"[BrowserHost] Extension script NOT FOUND at: {extensionPath}");
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[BrowserHost] Failed to inject extension: {ex.Message}");
                        Console.WriteLine($"[BrowserHost] Exception stack: {ex.StackTrace}");
                    }
                }

                if (_parentHwnd != IntPtr.Zero)
                {
                    EmbedToParent();
                    CreateToggleButton();
                }
                else
                {
                    _container!.Show();
                }

                _webView.CoreWebView2.Navigate($"http://localhost:{_currentPort}/index.html");
                Console.WriteLine($"[BrowserHost] ������: http://localhost:{_currentPort}/index.html");
                Console.WriteLine($"[BrowserHost] NavigationCompleted handler ��ע�ᣬ�ȴ�ҳ�����...");
                Console.WriteLine($"[BrowserHost] _webView.CoreWebView2 ����: {_webView.CoreWebView2 != null}");

                // �ӳ� 3 ����� Host Objects �Ƿ�ע�루���ڵ��ԣ�
                await Task.Delay(3000);
                Console.WriteLine($"[BrowserHost] �ӳټ�����");

                // ��ϣ���� Host Object �Ƿ��� JavaScript �п���
                try
                {
                    var result = await _webView.CoreWebView2.ExecuteScriptAsync(
                        "JSON.stringify({" +
                        "  hasChrome: !!window.chrome," +
                        "  hasWebview: !!(window.chrome && window.chrome.webview)," +
                        "  hasHostObjects: !!(window.chrome && window.chrome.webview && window.chrome.webview.hostObjects)," +
                        "  hasBrowserHost: !!(window.chrome && window.chrome.webview && window.chrome.webview.hostObjects && window.chrome.webview.hostObjects.browserHost)," +
                        "  hasSyncBrowserHost: !!(window.chrome && window.chrome.webview && window.chrome.webview.hostObjects && window.chrome.webview.hostObjects.sync && window.chrome.webview.hostObjects.sync.browserHost)" +
                        "})"
                    );
                    Console.WriteLine($"[BrowserHost] Host Object ���: {result}");
                }
                catch (Exception diagEx)
                {
                    Console.WriteLine($"[BrowserHost] Host Object ���ʧ��: {diagEx.Message}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] ��ʼ��ʧ��: {ex.Message}");
                MessageBox.Show($"WebView2 ��ʼ��ʧ��: {ex.Message}", "����", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void EmbedToParent()
        {
            if (_parentHwnd == IntPtr.Zero || _webView == null || _container == null) return;

            try
            {
                // ��鸸�����Ƿ���Ч
                if (!IsWindow(_parentHwnd))
                {
                    Console.WriteLine($"[BrowserHost] ��������Ч (0x{_parentHwnd:X})������Ƕ��");
                    return;
                }

                IntPtr containerHwnd = _container.Handle;
                Console.WriteLine($"[BrowserHost] �������: {containerHwnd}");

                if (containerHwnd == IntPtr.Zero)
                {
                    Console.WriteLine("[BrowserHost] �������Ϊ 0���ȴ�...");
                    var timer = new System.Windows.Forms.Timer();
                    timer.Interval = 500;
                    timer.Tick += (s, e) =>
                    {
                        timer.Stop();
                        timer.Dispose();
                        if (_container != null && _container.Handle != IntPtr.Zero)
                        {
                            EmbedToParent();
                        }
                    };
                    timer.Start();
                    return;
                }

                // �����ó�ʼ���ڴ�С
                UpdateContainerSize();

                // �� SetParent
                var result = SetParent(containerHwnd, _parentHwnd);
                Console.WriteLine($"[BrowserHost] SetParent ���: {result}");

                // ��� WS_EX_CLIENTEDGE ��չ��ʽ����ᵼ������������������
                int exStyle = NativeMethods.GetWindowLong(containerHwnd, -20); // GWL_EXSTYLE = -20
                if ((exStyle & 0x200) != 0) // WS_EX_CLIENTEDGE = 0x200
                {
                    NativeMethods.SetWindowLong(containerHwnd, -20, exStyle & ~0x200);
                    DebugLog($"[EmbedToParent] ��� WS_EX_CLIENTEDGE, ԭ��ʽ={exStyle}");
                    // �ô�������Ӧ����ʽ
                    SetWindowPos(containerHwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0040 | 0x0001); // SWP_FRAMECHANGED | SWP_NOACTIVATE
                }

                ShowWindow(containerHwnd, SW_SHOW);
                if (_webView != null)
                {
                    _webView.Visible = true;
                    _webView.BringToFront();
                }

                // SetParent �������ٴ����óߴ磬ȷ��������ȷ�ĸ����ڳߴ�
                UpdateContainerSize();

                // ���ڸ���λ�úʹ�С
                _resizeTimer = new System.Windows.Forms.Timer();
                _resizeTimer.Interval = 100;
                _resizeTimer.Tick += (s, e) => UpdateContainerSize();
                _resizeTimer.Start();

                Console.WriteLine("[BrowserHost] ����Ƕ�����");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] Ƕ��ʧ��: {ex.Message}");
            }
        }

        private void UpdateContainerSize()
        {
            if (_parentHwnd == IntPtr.Zero || _container == null) return;

            try
            {
                RECT parentRect;
                if (!GetClientRect(_parentHwnd, out parentRect))
                {
                    DebugLog($"[UpdateContainerSize] GetClientRect failed, fallback to GetWindowRect");
                    if (!GetWindowRect(_parentHwnd, out parentRect))
                    {
                        DebugLog($"[UpdateContainerSize] GetWindowRect also failed");
                        return;
                    }
                }
                DebugLog($"[UpdateContainerSize] Using rect: {parentRect.Right - parentRect.Left}x{parentRect.Bottom - parentRect.Top}");

                int parentWidth = parentRect.Right - parentRect.Left;
                int parentHeight = parentRect.Bottom - parentRect.Top;

                // ǿ����С�߶ȣ���ֹ�����С�ߴ磨�� 48px��
                // ����Ҫ����ǿ�ƣ�����������ʵ�ʿͻ����ߴ�
                const int MIN_WIDTH = 400;
                const int MIN_HEIGHT = 400;
                if (parentWidth < MIN_WIDTH) parentWidth = MIN_WIDTH;
                if (parentHeight < MIN_HEIGHT) parentHeight = MIN_HEIGHT;

                if (parentWidth == _lastParentWidth && parentHeight == _lastParentHeight)
                    return;

                _lastParentWidth = parentWidth;
                _lastParentHeight = parentHeight;

                Console.WriteLine($"[BrowserHost] �����ڳߴ�: {parentWidth}x{parentHeight}");

                // �Ӵ���λ������ڸ����ڿͻ���
                SetWindowPos(_container.Handle, IntPtr.Zero, 0, 0, parentWidth, parentHeight,
                    SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW);

                _container!.Width = parentWidth;
                _container!.Height = parentHeight;

                if (_webView != null)
                {
                    _webView.Width = parentWidth;
                    _webView.Height = parentHeight;
                }

                Console.WriteLine($"[BrowserHost] �����ѵ���: {_container!.Width}x{_container!.Height}");

                UpdateToggleButton();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] ������Сʧ��: {ex.Message}");
            }
        }

        private void CreateToggleButton()
        {
                        if (_container == null) return;

            // ����������壨Ĭ���۵�����ࣩ
            _drawerPanel = new Panel();
            _drawerPanel.Name = "DrawerPanel";
            _drawerPanel.Size = new System.Drawing.Size(DRAWER_WIDTH, _container.Height);
            _drawerPanel.Location = new System.Drawing.Point(-DRAWER_WIDTH, 0);
            _drawerPanel.BackColor = System.Drawing.Color.FromArgb(20, 25, 35);
            _drawerPanel.AutoScroll = false;
            _drawerPanel.Padding = new Padding(0);
            _drawerPanel.Margin = new Padding(0);
            _drawerPanel.BorderStyle = BorderStyle.None;

            // ����������������
            var drawerContent = new VStackPanel();
            drawerContent.Name = "DrawerContent";
            drawerContent.Dock = DockStyle.Fill;
            drawerContent.BackColor = Color.Transparent;
            _drawerPanel.Controls.Add(drawerContent);

            // ����������ҳ��ť
            var homeBtn = new DrawerMenuButton("⌂ 首页", 44);
            homeBtn.Dock = DockStyle.Top;
            homeBtn.Click += async (s, e) =>
            {
                Console.WriteLine("[BrowserHost] ����˵�: ������ҳ");
                if (_webView?.CoreWebView2 != null)
                {
                    // ȡ���κι�������󣬷�ֹ�̳߳ؼ���
                    Program.CancelPendingRequests();

                    // ���ʵ�ʿ��õĶ˿ڣ�����ʱ���ƣ�
                    var availablePort = await _detectAvailablePortWithTimeoutAsync();
                    Console.WriteLine($"[BrowserHost] ������ҳ����⵽���ö˿�: {availablePort}");
                    // ʹ�� hash ·�� #mods������������ index.html��JavaScript ��� hash �л�ҳ��
                    _webView.CoreWebView2.Navigate($"http://localhost:{availablePort}/index.html#mods");
                }
                CloseDrawer();
            };
            drawerContent.Controls.Add(homeBtn);

            // ����ˢ��ҳ�水ť
            var refreshBtn = new DrawerMenuButton("↻ 刷新", 44);
            refreshBtn.Dock = DockStyle.Top;
            refreshBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] ����˵�: ˢ��ҳ��");
                if (_webView?.CoreWebView2 != null)
                {
                    _webView.CoreWebView2.Reload();
                    Console.WriteLine("[BrowserHost] ҳ����ˢ��");
                }
                CloseDrawer();
            };
            drawerContent.Controls.Add(refreshBtn);

            // ��������ҳ��
            var configPage = new ConfigPage();
            configPage.Visible = false;
            configPage.Dock = DockStyle.Fill;
            drawerContent.Controls.Add(configPage);

            // �������ð�ť
            var configBtn = new DrawerMenuButton("⚙ 配置", 44);
            configBtn.Dock = DockStyle.Top;
            configBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] ����˵�: ����");
                // ���ز˵�����ʾ����ҳ��
                foreach (Control c in drawerContent.Controls)
                {
                    c.Visible = false;
                }
                configPage.Visible = true;
                configPage.BringToFront();
            };
            drawerContent.Controls.Add(configBtn);

            // �����ļ�ҳ�棬���ڷ��ز˵�
            configPage.OnBack += () =>
            {
                configPage.Reset();
                configPage.Visible = false;
                foreach (Control c in drawerContent.Controls)
                {
                    if (c != configPage)
                        c.Visible = true;
                }
            };

            // ����˿�
            configPage.OnSavePort += (port) =>
            {
                _updatePort(port);
                MessageBox.Show("�˿��ѱ��棬��Ҫ����Ӧ�ó��������Ч��", "��ʾ", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };

            // ��������
            configPage.OnRestartService += () =>
            {
                Console.WriteLine("[BrowserHost] �������ط���...");
                // ���µ�������ǰ�˿�ˢ������
                if (_webView?.CoreWebView2 != null)
                {
                    _webView.CoreWebView2.Navigate($"http://localhost:{_currentPort}/index.html");
                }
                MessageBox.Show("������������", "��ʾ", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };

            // ������沢ˢ��
            configPage.OnClearCache += () =>
            {
                Console.WriteLine("[BrowserHost] ������沢ˢ��...");
                if (_webView?.CoreWebView2 != null)
                {
                    _webView.CoreWebView2.Navigate($"http://localhost:{_currentPort}/index.html");
                }
                MessageBox.Show("�����������ҳ����ˢ�¡�", "��ʾ", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };

            // ������ - ֱ�ӵ��� API �������������ԭ�� STS2Settings.checkForUpdates ����һ��
            configPage.OnCheckUpdates += () =>
            {
                Console.WriteLine("[BrowserHost] ������...");
                if (_webView?.CoreWebView2 != null)
                {
                    string script = "(async function() { " +
                        "try { " +
                        "console.log('[BrowserHost] Starting update check...'); " +
                        "if (window.STS2Settings && window.STS2Settings._app && window.STS2Settings._app.notifications) { " +
                        "console.log('[BrowserHost] Using STS2Settings.checkForUpdates'); " +
                        "await window.STS2Settings.checkForUpdates(); " +
                        "} else { " +
                        "console.log('[BrowserHost] STS2Settings not ready, using API directly'); " +
                        "const resp = await window.api.checkUpdate(); " +
                        "console.log('[BrowserHost] API response:', JSON.stringify(resp)); " +
                        "const data = resp.data || {}; " +
                        "const currentVersion = data.current_version || 'v2.9.5'; " +
                        "if (data.has_update) { " +
                        "window.chrome?.webview?.hostObjects?.browserHost?.ShowUpdateDialog(currentVersion, data.new_version || '?', data.changelog || '', data.download_url || ''); " +
                        "} else { " +
                        "const msg = 'Already at latest version ' + currentVersion; " +
                        "if (window.app?.notifications) { window.app.notifications.show(msg, 'success', 3000); } " +
                        "console.log('[BrowserHost] ' + msg); " +
                        "} " +
                        "} " +
                        "} catch(e) { console.error('[BrowserHost] update check error:', e.message); } " +
                        "})()";
                    _webView.CoreWebView2.ExecuteScriptAsync(script);
                }
            };

            // �����ָ���
            var sep1 = new Panel();
            sep1.Name = "Sep1";
            sep1.Size = new System.Drawing.Size(DRAWER_WIDTH - 20, 1);
            sep1.BackColor = System.Drawing.Color.FromArgb(60, 70, 90);
            sep1.Dock = DockStyle.Top;
            sep1.Margin = new Padding(10, 10, 10, 0);
            drawerContent.Controls.Add(sep1);

            // ��������ԭ�水ť
            var vanillaBtn = new DrawerMenuButton("▶ 启动原版", 44);
            vanillaBtn.Dock = DockStyle.Top;
            vanillaBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] ����˵�: ����ԭ��");
                System.Diagnostics.Process.Start("steam://launch/2868840");
                CloseDrawer();
            };
            drawerContent.Controls.Add(vanillaBtn);

            // ��������ģ��水ť
            var moddedBtn = new DrawerMenuButton("▶ 启动模组版", 44);
            moddedBtn.Dock = DockStyle.Top;
            moddedBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] ����˵�: ����ģ���");
                System.Diagnostics.Process.Start("steam://launch/2868840/dialog");
                CloseDrawer();
            };
            drawerContent.Controls.Add(moddedBtn);

            // �����ָ���
            var sep2 = new Panel();
            sep2.Name = "Sep2";
            sep2.Size = new System.Drawing.Size(DRAWER_WIDTH - 20, 1);
            sep2.BackColor = System.Drawing.Color.FromArgb(60, 70, 90);
            sep2.Dock = DockStyle.Top;
            sep2.Margin = new Padding(10, 10, 10, 0);
            drawerContent.Controls.Add(sep2);

            // �����˳���ť
            var exitBtn = new DrawerMenuButton("✕ 退出", 44);
            exitBtn.Dock = DockStyle.Top;
            exitBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] ����˵�: �˳�");
                Environment.Exit(0);
            };
            drawerContent.Controls.Add(exitBtn);

            _container.Controls.Add(_drawerPanel);
            _drawerPanel.BringToFront();

            // ���� Toggle ��ť
            _toggleBtn = new ToggleButton();
            _toggleBtn.Name = "ToggleDrawer";
            _toggleBtn.Size = new System.Drawing.Size(TOGGLE_WIDTH_COLLAPSED, TOGGLE_HEIGHT);
            _toggleBtn.Location = new System.Drawing.Point(0, (_container.Height - TOGGLE_HEIGHT) / 2);

            _container.Controls.Add(_toggleBtn);
            _toggleBtn.BringToFront();

            // ����뿪ʱ�ӳ�����
            _toggleBtn.MouseLeave += (s, e) =>
            {
                _isHovering = false;
                if (!_isDrawerOpen)
                {
                    var timer = new System.Windows.Forms.Timer();
                    timer.Interval = 300;
                    timer.Tick += (ts, te) =>
                    {
                        timer.Stop();
                        timer.Dispose();
                        if (!_isHovering && !_isDrawerOpen)
                            CollapseToggleButton();
                    };
                    timer.Start();
                }
            };

            _toggleBtn.Click += (s, e) =>
            {
                if (_isDrawerOpen) CloseDrawer();
                else OpenDrawer();
            };

            // ������ʱ����ѯ������λ��
            _mouseCheckTimer = new System.Windows.Forms.Timer();
            _mouseCheckTimer.Interval = 50;  // ÿ 50ms ���һ��
            _mouseCheckTimer.Tick += (s, e) => OnMouseCheckTick();
            _mouseCheckTimer.Start();

            Console.WriteLine("[BrowserHost] DrawerToggleButton �Ѵ���");
        }

        private void OnMouseCheckTick()
        {
            if (_toggleBtn == null || _container == null) return;

            // ����չ��ʱ����������ͣ�߼�
            if (_isDrawerOpen) return;

            var mouseScreenPos = System.Windows.Forms.Control.MousePosition;

            var btnScreenLoc = _toggleBtn.PointToScreen(new System.Drawing.Point(0, 0));
            var btnSize = _toggleBtn.Size;

            var detectRect = new System.Drawing.Rectangle(
                btnScreenLoc.X - 80,
                btnScreenLoc.Y - 20,
                btnSize.Width + 110,
                btnSize.Height + 40);

            bool shouldHover = detectRect.Contains(mouseScreenPos);

            if (shouldHover)
            {
                if (!_isHovering)
                {
                    _isHovering = true;
                    ExpandToggleButton();
                }
            }
            else
            {
                if (_isHovering)
                {
                    _isHovering = false;
                    var timer = new System.Windows.Forms.Timer();
                    timer.Interval = 500;
                    timer.Tick += (ts, te) =>
                    {
                        timer.Stop();
                        timer.Dispose();
                        if (!_isHovering && !_isDrawerOpen)
                            CollapseToggleButton();
                    };
                    timer.Start();
                }
            }
        }

        private System.Drawing.Drawing2D.GraphicsPath CreateRoundedRectRight(System.Drawing.Rectangle rect, int radius)
        {
            var path = new System.Drawing.Drawing2D.GraphicsPath();
            // ����Բ�ǰ뾶
            radius = Math.Min(radius, rect.Width / 2 - 1);
            // ����̫Сʱ����Բ�ǣ�ֱ���þ���
            if (radius <= 1 || rect.Width <= 8)
            {
                path.AddRectangle(rect);
                return path;
            }
            int diameter = radius * 2;
            int right = rect.Right;
            int bottom = rect.Bottom;

            // �Ӷ��߿�ʼ��˳ʱ�����
            path.AddLine(rect.Left, rect.Top + radius, right - radius, rect.Top);  // �ϱ�
            path.AddArc(right - diameter, rect.Top, diameter, diameter, 270, 90);   // ����Բ��
            path.AddArc(right - diameter, bottom - diameter, diameter, diameter, 0, 90); // ����Բ��
            path.AddLine(rect.Left, bottom, right - radius, bottom);                // �±�
            path.AddLine(rect.Left, bottom, rect.Left, rect.Top + radius);              // ��ߣ�ֱ�ǣ�
            path.CloseFigure();
            return path;
        }

        private void ExpandToggleButton()
        {
            if (_toggleBtn == null) return;

            if (_toggleBtn is ToggleButton tb)
            {
                tb.Expand();
            }
        }

        private void CollapseToggleButton()
        {
            if (_toggleBtn == null || _isDrawerOpen) return;

            if (_toggleBtn is ToggleButton tb)
            {
                tb.Collapse();
            }
        }

        private void OpenDrawer()
        {
            if (_drawerPanel == null || _isDrawerOpen) return;
            _isDrawerOpen = true;
            _isAnimating = true;
            // ȷ���������ɼ�
            if (_drawerPanel != null)
            {
                _drawerPanel.Visible = true;
                Console.WriteLine("[BrowserHost] OpenDrawer: DrawerPanel ����ʾ");
            }

            var tween = new System.Windows.Forms.Timer();
            tween.Interval = ANIM_INTERVAL;
            int step = 0;
            int startX = -DRAWER_WIDTH;
            int endX = 0;

            tween.Tick += (s, e) =>
            {
                step++;
                int newX = startX + (endX - startX) * step / ANIM_STEPS;
                _drawerPanel.Location = new System.Drawing.Point(newX, 0);

                // ToggleButton �����ƶ�
                if (_toggleBtn != null)
                {
                    int btnNewX = newX + DRAWER_WIDTH;
                    _toggleBtn.Location = new System.Drawing.Point(btnNewX, _toggleBtn.Location.Y);
                }

                if (step >= ANIM_STEPS)
                {
                    tween.Stop();
                    _isAnimating = false;
                    // ������������ť���浽�����ұ�
                    if (_toggleBtn != null)
                    {
                        _toggleBtn.Location = new System.Drawing.Point(DRAWER_WIDTH, _toggleBtn.Location.Y);
                    }
                }
            };
            tween.Start();
        }

        private void CloseDrawer()
        {
            if (_drawerPanel == null || !_isDrawerOpen) return;
            _isDrawerOpen = false;
            _isAnimating = true;

            var tween = new System.Windows.Forms.Timer();
            tween.Interval = ANIM_INTERVAL;
            int step = 0;
            int startX = 0;
            int endX = -DRAWER_WIDTH;

            tween.Tick += (s, e) =>
            {
                step++;
                int newX = startX + (endX - startX) * step / ANIM_STEPS;
                _drawerPanel.Location = new System.Drawing.Point(newX, 0);

                // ToggleButton ��������ƶ����������λ�ã�
                if (_toggleBtn != null)
                {
                    int btnNewX = newX + DRAWER_WIDTH;
                    _toggleBtn.Location = new System.Drawing.Point(btnNewX, _toggleBtn.Location.Y);
                }

                if (step >= ANIM_STEPS)
                {
                    tween.Stop();
                    _isAnimating = false;
                    // �������������س�����壬������Ӱ����
                    if (_drawerPanel != null)
                    {
                        _drawerPanel.Visible = false;
                        Console.WriteLine("[BrowserHost] CloseDrawer: DrawerPanel ������");
                    }
                }
            };
            tween.Start();
        }

        private System.Drawing.Drawing2D.GraphicsPath CreateRoundedRect(System.Drawing.Rectangle rect, int radius)
        {
            var path = new System.Drawing.Drawing2D.GraphicsPath();
            int diameter = radius * 2;
            path.AddArc(rect.X, rect.Y, diameter, diameter, 180, 90);
            path.AddArc(rect.Right - diameter, rect.Y, diameter, diameter, 270, 90);
            path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rect.X, rect.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private void UpdateToggleButton()
        {
            if (_toggleBtn == null || _container == null) return;

            // ��ť�����������Ե����ֱ����
            _toggleBtn.Location = new System.Drawing.Point(0, (_container.Height - TOGGLE_HEIGHT) / 2);
            _toggleBtn.BringToFront();
        }

        [DllImport("user32.dll")]
        private static extern bool DestroyMenu(IntPtr hMenu);

        // ��ʾ���µ��� - ����������ʾ���ǲ�
        private void ShowUpdateDialog(string currentVersion, string newVersion, string changelog, string downloadUrl)
        {
            Console.WriteLine($"[BrowserHost] ShowUpdateDialog called: current={currentVersion}, new={newVersion}");

            if (_container == null) return;

            // ���� ToggleButton ���ã��������رպ�ָ�
            var toggleBtnRef = _toggleBtn;
            if (toggleBtnRef != null)
            {
                toggleBtnRef.Visible = false;
                Console.WriteLine("[BrowserHost] ���� ToggleButton");
            }

            // �����̴߳�������ʾ���
            if (_container.InvokeRequired)
            {
                _container.Invoke(new Action(() =>
                {
                    ShowUpdateDialogInternal(currentVersion, newVersion, changelog, downloadUrl, toggleBtnRef);
                }));
            }
            else
            {
                ShowUpdateDialogInternal(currentVersion, newVersion, changelog, downloadUrl, toggleBtnRef);
            }
        }

        private void ShowUpdateDialogInternal(string currentVersion, string newVersion, string changelog, string downloadUrl, ToggleButton? toggleBtnRef)
        {
            // ��ʾ����ʱ�ȹرճ��벢��ȫ���أ����ⱳ������
            CloseDrawer();
            // ��ȫ���س�����壬������Ӱ��ʾ
            if (_drawerPanel != null)
            {
                _drawerPanel.Visible = false;
                Console.WriteLine("[BrowserHost] ���� DrawerPanel");
            }

            // ���������Ѵ��ڵĸ��µ�������ֹ�ظ����ӣ�
            if (_container != null)
            {
                var toRemove = new List<Control>();
                foreach (Control c in _container.Controls)
                {
                    if (c is UpdateDialogPanel)
                    {
                        toRemove.Add(c);
                    }
                }
                foreach (var c in toRemove)
                {
                    _container.Controls.Remove(c);
                    c.Dispose();
                    Console.WriteLine("[BrowserHost] �Ƴ��ɵ���: " + c.Name);
                }
            }
            _updateDialogPanel = null;

            // �����µĸ��µ������
            _updateDialogPanel = new UpdateDialogPanel(currentVersion, newVersion, changelog);
            _updateDialogPanel.OnUpdateNow += () =>
            {
                Console.WriteLine("[BrowserHost] �û�ѡ���������£�����Godot���ظ���");
                // ����Web API����Godot���ظ���
                if (_webView?.CoreWebView2 != null)
                {
                    var script = $@"
                        (async () => {{
                            try {{
                                const result = await window.api.downloadUpdate('{downloadUrl.Replace("'", "\\'")}');
                                console.log('[BrowserHost] ���ظ���API����:', result);
                            }} catch(e) {{
                                console.error('[BrowserHost] �������ظ���APIʧ��:', e.message);
                            }}
                        }})()
                    ";
                    _webView.CoreWebView2.ExecuteScriptAsync(script);
                }
                else
                {
                    Console.WriteLine("[BrowserHost] WebView2δ�������޷���������API");
                }
                // �رյ���������
                if (_updateDialogPanel != null)
                {
                    _updateDialogPanel.Visible = false;
                    _container.Controls.Remove(_updateDialogPanel);
                    _updateDialogPanel.Dispose();
                    _updateDialogPanel = null;
                    Console.WriteLine("[BrowserHost] ���µ����ѹرղ�����");
                }
                // �ָ� ToggleButton
                if (toggleBtnRef != null) toggleBtnRef.Visible = true;
            };
            _updateDialogPanel.OnLater += () =>
            {
                Console.WriteLine("[BrowserHost] �û�ѡ���Ժ����");
                // �رյ���������
                if (_updateDialogPanel != null)
                {
                    _updateDialogPanel.Visible = false;
                    _container.Controls.Remove(_updateDialogPanel);
                    _updateDialogPanel.Dispose();
                    _updateDialogPanel = null;
                    Console.WriteLine("[BrowserHost] ���µ����ѹرղ�����");
                }
                // �ָ� ToggleButton
                if (toggleBtnRef != null) toggleBtnRef.Visible = true;
            };

            // ���ӵ���������ʾ
            _container.Controls.Add(_updateDialogPanel);
            _updateDialogPanel.BringToFront();
            _updateDialogPanel.ShowWithAnimation();

            Console.WriteLine("[BrowserHost] UpdateDialogPanel ����ʾ");
        }

        // ����ҳ�� - �ڳ�������ʾ��ҳ����
        class ConfigPage : Panel
        {
            public event Action? OnBack;
            public event Action<int>? OnSavePort;
            public event Action? OnRestartService;
            public event Action? OnClearCache;
            public event Action? OnCheckUpdates;

            private Button _backBtn;
            private Label _titleLabel;
            private Label _portLabel;
            private TextBox _portInput;
            private Button _saveBtn;
            private Label _versionLabel;
            private Button _restartBtn;
            private Button _clearCacheBtn;
            private Button _checkUpdateBtn;
            private Label _updateStatusLabel;

            public ConfigPage()
            {
                this.BackColor = Color.FromArgb(20, 25, 35);
                this.Dock = DockStyle.Fill;
                DoubleBuffered = true;
                SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint, true);

                // ���ذ�ť
                _backBtn = new Button();
                _backBtn.Text = "�� ����";
                _backBtn.Size = new Size(80, 32);
                _backBtn.Location = new Point(10, 10);
                _backBtn.FlatStyle = FlatStyle.Flat;
                _backBtn.BackColor = Color.FromArgb(30, 40, 55);
                _backBtn.ForeColor = Color.FromArgb(180, 185, 200);
                _backBtn.Cursor = Cursors.Hand;
                _backBtn.Click += (s, e) => OnBack?.Invoke();
                this.Controls.Add(_backBtn);

                // ����
                _titleLabel = new Label();
                _titleLabel.Text = "����������";
                _titleLabel.Font = new Font("Segoe UI", 12f, FontStyle.Bold);
                _titleLabel.ForeColor = Color.FromArgb(200, 220, 240);
                _titleLabel.Location = new Point(10, 60);
                _titleLabel.AutoSize = true;
                this.Controls.Add(_titleLabel);

                // �˿�����
                _portLabel = new Label();
                _portLabel.Text = "�˿�:";
                _portLabel.Font = new Font("Segoe UI", 10f);
                _portLabel.ForeColor = Color.FromArgb(180, 185, 200);
                _portLabel.Location = new Point(10, 110);
                _portLabel.AutoSize = true;
                this.Controls.Add(_portLabel);

                _portInput = new TextBox();
                _portInput.Text = "28900";
                _portInput.Size = new Size(100, 28);
                _portInput.Location = new Point(60, 106);
                _portInput.BackColor = Color.FromArgb(30, 40, 55);
                _portInput.ForeColor = Color.FromArgb(200, 205, 220);
                _portInput.BorderStyle = BorderStyle.FixedSingle;
                _portInput.Font = new Font("Segoe UI", 10f);
                this.Controls.Add(_portInput);

                _saveBtn = new Button();
                _saveBtn.Text = "����";
                _saveBtn.Size = new Size(80, 32);
                _saveBtn.Location = new Point(170, 104);
                _saveBtn.FlatStyle = FlatStyle.Flat;
                _saveBtn.BackColor = Color.FromArgb(60, 90, 140);
                _saveBtn.ForeColor = Color.White;
                _saveBtn.Cursor = Cursors.Hand;
                _saveBtn.Click += (s, e) =>
                {
                    int port;
                    if (int.TryParse(_portInput.Text, out port) && port >= 1024 && port <= 65535)
                    {
                        Console.WriteLine($"[BrowserHost] ����˿�: {port}");
                        OnSavePort?.Invoke(port);
                    }
                    else
                    {
                        Console.WriteLine($"[BrowserHost] ��Ч�˿�: {_portInput.Text}");
                    }
                };
                this.Controls.Add(_saveBtn);

                // �汾��Ϣ
                _versionLabel = new Label();
                _versionLabel.Text = "��ǰ�汾: v1.0.0";
                _versionLabel.Font = new Font("Segoe UI", 10f);
                _versionLabel.ForeColor = Color.FromArgb(150, 155, 170);
                _versionLabel.Location = new Point(10, 160);
                _versionLabel.AutoSize = true;
                this.Controls.Add(_versionLabel);

                // ��������ť
                _restartBtn = new Button();
                _restartBtn.Text = "��������";
                _restartBtn.Size = new Size(110, 32);
                _restartBtn.Location = new Point(10, 210);
                _restartBtn.FlatStyle = FlatStyle.Flat;
                _restartBtn.BackColor = Color.FromArgb(30, 40, 55);
                _restartBtn.ForeColor = Color.FromArgb(180, 185, 200);
                _restartBtn.Cursor = Cursors.Hand;
                _restartBtn.Click += (s, e) =>
                {
                    Console.WriteLine("[BrowserHost] ��������");
                    OnRestartService?.Invoke();
                };
                this.Controls.Add(_restartBtn);

                // ������沢ˢ�°�ť
                _clearCacheBtn = new Button();
                _clearCacheBtn.Text = "������沢ˢ��";
                _clearCacheBtn.Size = new Size(130, 32);
                _clearCacheBtn.Location = new Point(130, 210);
                _clearCacheBtn.FlatStyle = FlatStyle.Flat;
                _clearCacheBtn.BackColor = Color.FromArgb(30, 40, 55);
                _clearCacheBtn.ForeColor = Color.FromArgb(180, 185, 200);
                _clearCacheBtn.Cursor = Cursors.Hand;
                _clearCacheBtn.Click += (s, e) =>
                {
                    Console.WriteLine("[BrowserHost] ������沢ˢ��");
                    OnClearCache?.Invoke();
                };
                this.Controls.Add(_clearCacheBtn);

                // �����°�ť
                _checkUpdateBtn = new Button();
                _checkUpdateBtn.Text = "������";
                _checkUpdateBtn.Size = new Size(110, 32);
                _checkUpdateBtn.Location = new Point(10, 260);
                _checkUpdateBtn.FlatStyle = FlatStyle.Flat;
                _checkUpdateBtn.BackColor = Color.FromArgb(30, 40, 55);
                _checkUpdateBtn.ForeColor = Color.FromArgb(180, 185, 200);
                _checkUpdateBtn.Cursor = Cursors.Hand;
                _checkUpdateBtn.Click += (s, e) =>
                {
                    Console.WriteLine("[BrowserHost] ������");
                    OnCheckUpdates?.Invoke();
                };
                this.Controls.Add(_checkUpdateBtn);

                // ����״̬��ǩ
                _updateStatusLabel = new Label();
                _updateStatusLabel.Text = "";
                _updateStatusLabel.Font = new Font("Segoe UI", 9f);
                _updateStatusLabel.ForeColor = Color.FromArgb(150, 155, 170);
                _updateStatusLabel.Location = new Point(130, 268);
                _updateStatusLabel.AutoSize = true;
                this.Controls.Add(_updateStatusLabel);
            }

            // ���ø���״̬�ı�
            public void SetUpdateStatus(string status)
            {
                _updateStatusLabel.Text = status;
            }

            // ����ҳ��״̬
            public void Reset()
            {
                _portInput.Text = "28900";
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(this.BackColor);
            }
        }

        // ����˵���ť - WebUI ���
        class DrawerMenuButton : Button
        {
            private bool _isHovered = false;
            private static readonly Color _normalBg = Color.FromArgb(30, 40, 55);
            private static readonly Color _hoverBg = Color.FromArgb(45, 60, 85);
            private static readonly Color _normalText = Color.FromArgb(180, 185, 200);
            private static readonly Color _hoverText = Color.FromArgb(100, 192, 250);
            private static readonly Color _borderColor = Color.FromArgb(50, 65, 90);

            public DrawerMenuButton(string text, int height)
            {
                this.Text = text;
                this.Height = height;
                this.Dock = DockStyle.Top;
                this.FlatStyle = FlatStyle.Flat;
                this.ForeColor = _normalText;
                this.BackColor = _normalBg;
                this.TextAlign = ContentAlignment.MiddleLeft;
                this.Padding = new Padding(12, 0, 12, 0);
                this.Cursor = Cursors.Hand;
                this.TabStop = false;
                this.DoubleBuffered = true;
                SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint, true);

                this.MouseEnter += (s, e) =>
                {
                    _isHovered = true;
                    this.BackColor = _hoverBg;
                    this.ForeColor = _hoverText;
                    this.Invalidate();
                };
                this.MouseLeave += (s, e) =>
                {
                    _isHovered = false;
                    this.BackColor = _normalBg;
                    this.ForeColor = _normalText;
                    this.Invalidate();
                };
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

                // ����
                using (var bgBrush = new SolidBrush(this.BackColor))
                {
                    g.FillRectangle(bgBrush, 0, 0, Width, Height);
                }

                // ��߸���������ͣʱ��ʾ��ɫָʾ����
                if (_isHovered)
                {
                    using (var indicatorBrush = new SolidBrush(Color.FromArgb(100, 192, 250)))
                    {
                        g.FillRectangle(indicatorBrush, 0, 0, 3, Height);
                    }
                }

                // ����
                using (var textBrush = new SolidBrush(this.ForeColor))
                using (var font = new Font("Segoe UI", 10f, FontStyle.Regular))
                {
                    var textSize = g.MeasureString(this.Text, font);
                    float x = 20f;
                    float y = (Height - textSize.Height) / 2;
                    g.DrawString(this.Text, font, textBrush, x, y);
                }
            }
        }

        // ��ֱ�ѵ���壨���ڳ������ݣ�
        class VStackPanel : Panel
        {
            public VStackPanel()
            {
                this.Dock = DockStyle.Fill;
                this.BackColor = Color.FromArgb(20, 25, 35);
            }
        }

        // �Զ��� ToggleButton - �򻯰汾��������Ⱦ����
        class ToggleButton : Panel
        {
            public event EventHandler? ExpandRequested;
            public event EventHandler? CollapseRequested;
            public event EventHandler? ClickRequested;

            private const int COLLAPSED_WIDTH = 20;
            private const int EXPANDED_WIDTH = 44;
            private const int HEIGHT = 44;

            private int _currentWidth = COLLAPSED_WIDTH;
            private System.Windows.Forms.Timer? _animTimer;
            private bool _isExpanded = false;
            private bool _isAnimating = false;
            private bool _isHovered = false;

            public ToggleButton()
            {
                this.Size = new System.Drawing.Size(COLLAPSED_WIDTH, HEIGHT);
                this.MinimumSize = new System.Drawing.Size(COLLAPSED_WIDTH, HEIGHT);
                this.MaximumSize = new System.Drawing.Size(EXPANDED_WIDTH, HEIGHT);
                this.BackColor = System.Drawing.Color.Transparent;
                this.Cursor = Cursors.Hand;
                this.Text = "";
                this.DoubleBuffered = true;
                this.SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint, true);
                this.SetStyle(ControlStyles.SupportsTransparentBackColor, true);

                this.MouseEnter += OnMouseEnter;
                this.MouseLeave += OnMouseLeave;
                this.MouseClick += OnMouseClick;
            }

            private void OnMouseEnter(object? sender, EventArgs e)
            {
                _isHovered = true;
                Invalidate();
                ExpandRequested?.Invoke(this, EventArgs.Empty);
            }

            private void OnMouseLeave(object? sender, EventArgs e)
            {
                _isHovered = false;
                Invalidate();
                if (!_isExpanded && !_isAnimating)
                    CollapseRequested?.Invoke(this, EventArgs.Empty);
            }

            private void OnMouseClick(object? sender, MouseEventArgs e)
            {
                ClickRequested?.Invoke(this, EventArgs.Empty);
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

                int w = Width;
                int h = Height;
                int r = 6;

                var path = new System.Drawing.Drawing2D.GraphicsPath();
                path.AddLine(0, 0, r, 0);
                path.AddArc(w - 2 * r, 0, 2 * r, 2 * r, 270, 90);
                path.AddLine(w, r, w, h - r);
                path.AddArc(w - 2 * r, h - 2 * r, 2 * r, 2 * r, 0, 90);
                path.AddLine(w - r, h, 0, h);
                path.AddLine(0, h, 0, 0);
                path.CloseFigure();

                // ��·����Ϊ�ü����򣬷�ֹ WinForms ��·������Ʊ���
                g.SetClip(path);

                using (var brush = new SolidBrush(System.Drawing.Color.FromArgb(60, 90, 140)))
                {
                    g.FillPath(brush, path);
                }
                path.Dispose();

                bool showHamburger = Width >= EXPANDED_WIDTH - 4;
                using (var pen = new Pen(System.Drawing.Color.FromArgb(200, 220, 240), 2))
                {
                    pen.StartCap = System.Drawing.Drawing2D.LineCap.Round;
                    pen.EndCap = System.Drawing.Drawing2D.LineCap.Round;
                    if (showHamburger)
                    {
                        int x1 = 8;
                        int x2 = Width - 8;
                        if (x2 > x1 + 4)
                        {
                            g.DrawLine(pen, x1, 12, x2, 12);
                            g.DrawLine(pen, x1, 22, x2, 22);
                            g.DrawLine(pen, x1, 32, x2, 32);
                        }
                    }
                    else
                    {
                        int cx = Width - 10;
                        if (cx > 4)
                        {
                            g.DrawLine(pen, cx - 4, 14, cx + 4, 22);
                            g.DrawLine(pen, cx + 4, 22, cx - 4, 30);
                        }
                    }
                }
            }

            public void Expand()
            {
                if (_isAnimating) return;
                _isAnimating = true;

                _animTimer?.Stop();
                _animTimer = new System.Windows.Forms.Timer();
                _animTimer.Interval = 16;
                int targetWidth = EXPANDED_WIDTH;
                int step = (targetWidth - _currentWidth) / 8;
                if (step < 1) step = 1;

                _animTimer.Tick += (s, e) =>
                {
                    if (_currentWidth < targetWidth)
                    {
                        _currentWidth = Math.Min(_currentWidth + step, targetWidth);
                        this.Width = _currentWidth;
                        Invalidate();
                    }
                    else
                    {
                        _animTimer.Stop();
                        _isAnimating = false;
                        _isExpanded = true;
                    }
                };
                _animTimer.Start();
            }

            public void Collapse()
            {
                if (_isAnimating) return;
                _isAnimating = true;

                _animTimer?.Stop();
                _animTimer = new System.Windows.Forms.Timer();
                _animTimer.Interval = 16;
                int targetWidth = COLLAPSED_WIDTH;
                int step = (_currentWidth - targetWidth) / 8;
                if (step < 1) step = 1;

                _animTimer.Tick += (s, e) =>
                {
                    if (_currentWidth > targetWidth)
                    {
                        _currentWidth = Math.Max(_currentWidth - step, targetWidth);
                        this.Width = _currentWidth;
                        Invalidate();
                    }
                    else
                    {
                        _animTimer.Stop();
                        _isAnimating = false;
                        _isExpanded = false;
                    }
                };
                _animTimer.Start();
            }

            public bool IsExpanded => _isExpanded;
        }

        // ���µ������ - �򻯰汾���޶�����������Ⱦ����
        class UpdateDialogPanel : Panel
        {
            public event Action? OnUpdateNow;
            public event Action? OnLater;

            private string _currentVersion;
            private string _newVersion;
            private string _changelog;

            public UpdateDialogPanel(string currentVersion, string newVersion, string changelog)
            {
                _currentVersion = currentVersion;
                _newVersion = newVersion;
                _changelog = changelog;

                // ������� - �����������
                this.Name = "UpdateDialogPanel";
                this.Dock = DockStyle.Fill;
                this.BackColor = Color.FromArgb(22, 28, 38);
                this.Padding = new Padding(0);
                this.Margin = new Padding(0);
                this.Visible = false;

                // ��������������壨��Ƭ��ʽ��
                var cardPanel = new Panel();
                cardPanel.Name = "CardPanel";
                cardPanel.Size = new Size(440, 380);
                cardPanel.BackColor = Color.FromArgb(35, 42, 55);
                cardPanel.BorderStyle = BorderStyle.None;

                // ����װ����
                var headerBar = new Panel();
                headerBar.Size = new Size(440, 4);
                headerBar.Location = new Point(0, 0);
                headerBar.BackColor = Color.FromArgb(60, 130, 200);
                cardPanel.Controls.Add(headerBar);

                // ͼ��ͱ�������
                var iconPanel = new Panel();
                iconPanel.Size = new Size(440, 60);
                iconPanel.Location = new Point(0, 20);
                iconPanel.BackColor = Color.Transparent;
                cardPanel.Controls.Add(iconPanel);

                // ����ͼ�꣨�� Label ģ�⣩
                var iconLabel = new Label();
                iconLabel.Text = "?";
                iconLabel.Font = new Font("Segoe UI", 28f, FontStyle.Regular);
                iconLabel.ForeColor = Color.FromArgb(60, 130, 200);
                iconLabel.Location = new Point(25, 0);
                iconLabel.AutoSize = true;
                iconPanel.Controls.Add(iconLabel);

                // ����������
                var titleLabel = new Label();
                titleLabel.Name = "TitleLabel";
                titleLabel.Text = "�����°汾";
                titleLabel.Font = new Font("Segoe UI", 18f, FontStyle.Bold);
                titleLabel.ForeColor = Color.FromArgb(220, 230, 245);
                titleLabel.Location = new Point(70, 8);
                titleLabel.AutoSize = true;
                iconPanel.Controls.Add(titleLabel);

                // �汾��Ϣ��ǩ
                var versionTag = new Panel();
                versionTag.Size = new Size(140, 24);
                versionTag.Location = new Point(285, 55);
                versionTag.BackColor = Color.FromArgb(60, 90, 140);
                cardPanel.Controls.Add(versionTag);

                var versionLabel = new Label();
                versionLabel.Name = "VersionLabel";
                versionLabel.Text = $"{_newVersion}";
                versionLabel.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
                versionLabel.ForeColor = Color.White;
                versionLabel.Location = new Point(8, 2);
                versionLabel.AutoSize = true;
                versionTag.Controls.Add(versionLabel);

                // ��ǰ�汾��Ϣ
                var currentVersionLabel = new Label();
                currentVersionLabel.Text = $"��ǰ�汾: {_currentVersion}";
                currentVersionLabel.Font = new Font("Segoe UI", 9f);
                currentVersionLabel.ForeColor = Color.FromArgb(140, 150, 165);
                currentVersionLabel.Location = new Point(25, 90);
                currentVersionLabel.AutoSize = true;
                cardPanel.Controls.Add(currentVersionLabel);

                // �ָ���
                var sep = new Panel();
                sep.Size = new Size(390, 1);
                sep.Location = new Point(25, 115);
                sep.BackColor = Color.FromArgb(70, 80, 100);
                cardPanel.Controls.Add(sep);

                // �������ݱ���
                var changelogTitle = new Label();
                changelogTitle.Text = "��������";
                changelogTitle.Font = new Font("Segoe UI", 11f, FontStyle.Bold);
                changelogTitle.ForeColor = Color.FromArgb(200, 210, 225);
                changelogTitle.Location = new Point(25, 125);
                changelogTitle.AutoSize = true;
                cardPanel.Controls.Add(changelogTitle);

                // ������־����
                var scrollPanel = new Panel();
                scrollPanel.Size = new Size(390, 145);
                scrollPanel.Location = new Point(25, 152);
                scrollPanel.BackColor = Color.FromArgb(28, 34, 45);
                scrollPanel.AutoScroll = true;
                scrollPanel.BorderStyle = BorderStyle.None;
                cardPanel.Controls.Add(scrollPanel);

                var changelogLabel = new Label();
                changelogLabel.Name = "ChangelogLabel";
                changelogLabel.Text = FormatChangelog(_changelog);
                changelogLabel.Font = new Font("Segoe UI", 9.5f);
                changelogLabel.ForeColor = Color.FromArgb(170, 180, 195);
                changelogLabel.Location = new Point(10, 10);
                changelogLabel.AutoSize = true;
                changelogLabel.MaximumSize = new Size(350, 0);
                scrollPanel.Controls.Add(changelogLabel);

                // ��ť���򱳾�
                var buttonPanelBg = new Panel();
                buttonPanelBg.Size = new Size(440, 65);
                buttonPanelBg.Location = new Point(0, 315);
                buttonPanelBg.BackColor = Color.FromArgb(30, 38, 50);
                cardPanel.Controls.Add(buttonPanelBg);

                // ��ť����
                var buttonPanel = new Panel();
                buttonPanel.Size = new Size(390, 45);
                buttonPanel.Location = new Point(25, 10);
                buttonPanel.BackColor = Color.Transparent;
                buttonPanelBg.Controls.Add(buttonPanel);

                // �Ժ���°�ť
                var laterBtn = new Button();
                laterBtn.Name = "LaterBtn";
                laterBtn.Text = "�Ժ����";
                laterBtn.Size = new Size(110, 38);
                laterBtn.Location = new Point(0, 4);
                laterBtn.FlatStyle = FlatStyle.Flat;
                laterBtn.BackColor = Color.FromArgb(55, 65, 80);
                laterBtn.ForeColor = Color.FromArgb(210, 215, 225);
                laterBtn.Cursor = Cursors.Hand;
                laterBtn.Font = new Font("Segoe UI", 10f);
                laterBtn.FlatAppearance.BorderColor = Color.FromArgb(80, 90, 110);
                laterBtn.FlatAppearance.BorderSize = 1;
                laterBtn.Click += (s, e) =>
                {
                    Console.WriteLine("[UpdateDialogPanel] �Ժ���� clicked");
                    OnLater?.Invoke();
                    this.Visible = false;
                };
                buttonPanel.Controls.Add(laterBtn);

                // �������°�ť
                var updateBtn = new Button();
                updateBtn.Name = "UpdateBtn";
                updateBtn.Text = "��������";
                updateBtn.Size = new Size(120, 38);
                updateBtn.Location = new Point(270, 4);
                updateBtn.FlatStyle = FlatStyle.Flat;
                updateBtn.BackColor = Color.FromArgb(60, 140, 220);
                updateBtn.ForeColor = Color.White;
                updateBtn.Cursor = Cursors.Hand;
                updateBtn.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
                updateBtn.FlatAppearance.BorderSize = 0;
                updateBtn.Click += (s, e) =>
                {
                    Console.WriteLine("[UpdateDialogPanel] �������� clicked");
                    OnUpdateNow?.Invoke();
                    // �ӳ����أ����¼��ȴ�����
                    this.Visible = false;
                };
                buttonPanel.Controls.Add(updateBtn);

                // ����Ƭ������ӵ�����
                this.Controls.Add(cardPanel);
                this.Resize += (s, e) =>
                {
                    int x = (this.Width - cardPanel.Width) / 2;
                    int y = (this.Height - cardPanel.Height) / 2;
                    cardPanel.Location = new Point(Math.Max(0, x), Math.Max(0, y));
                };
                // ��ʼ����
                cardPanel.Location = new Point((this.Width - cardPanel.Width) / 2, (this.Height - cardPanel.Height) / 2);

                // ��������ر�
                this.Click += (s, e) =>
                {
                    if (s == this)
                    {
                        OnLater?.Invoke();
                        this.Visible = false;
                    }
                };
            }

            private string FormatChangelog(string changelog)
            {
                if (string.IsNullOrEmpty(changelog))
                    return "���޸���˵��";

                var lines = changelog.Split('\n');
                var result = new System.Text.StringBuilder();
                foreach (var line in lines)
                {
                    var trimmed = line.Trim();
                    if (trimmed.StartsWith("- ") || trimmed.StartsWith("* "))
                    {
                        result.AppendLine("? " + trimmed.Substring(2));
                    }
                    else if (trimmed.StartsWith("##"))
                    {
                        result.AppendLine(trimmed.TrimStart('#').Trim());
                    }
                    else
                    {
                        result.AppendLine(trimmed);
                    }
                }
                return result.ToString().Trim();
            }

            public void ShowWithAnimation()
            {
                // �޶�����ֱ����ʾ
                this.Visible = true;
                this.BringToFront();

                // ���п�Ƭ
                var card = this.Controls["CardPanel"];
                if (card != null)
                {
                    int x = (this.Width - card.Width) / 2;
                    int y = (this.Height - card.Height) / 2;
                    card.Location = new Point(Math.Max(0, x), Math.Max(0, y));
                }
                Console.WriteLine("[UpdateDialogPanel] ����ʾ");
            }

            public void HideWithAnimation()
            {
                // �޶�����ֱ������
                this.Visible = false;
                Console.WriteLine("[UpdateDialogPanel] ������");
            }
        }
    }
}
