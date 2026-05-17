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
using System.Net.Http;

namespace BrowserHost
{
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
        // 更新弹窗回调
        private Action<string, string, string, string>? _showUpdateDialogCallback;
        // 导航回调
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
                dialog.Description = "选择导出目录";
                dialog.UseDescriptionForTitle = true;
                dialog.ShowNewFolderButton = true;
                if (dialog.ShowDialog() == DialogResult.OK)
                {
                    return dialog.SelectedPath;
                }
            }
            return null;
        }

        // 选择本地 ZIP 文件进行导入
        public string SelectBundleFile()
        {
            using (var dialog = new OpenFileDialog())
            {
                dialog.Filter = "整合包文件 (*.zip)|*.zip|所有文件 (*.*)|*.*";
                dialog.Title = "选择整合包";
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
                // 取消任何挂起的 HTTP 请求，防止线程池饥饿
                Program.CancelPendingRequests();

                var port = Program.GetCurrentPort();

                // 使用 hash 路由 #mods，服务器返回 index.html，JavaScript 检测 hash 切换页面
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

                // Forward to Godot backend API using sync call
                var httpClient = new System.Net.Http.HttpClient();
                httpClient.Timeout = TimeSpan.FromSeconds(30);

                // Cancel any pending download request first (prevent thread pool starvation)
                Program.CancelPendingRequests();

                var content = new StringContent(jsonData ?? "{}", System.Text.Encoding.UTF8, "application/json");
                var response = httpClient.PostAsync($"http://localhost:{Program.GetCurrentPort()}/api/download", content).GetAwaiter().GetResult();

                if (response.IsSuccessStatusCode)
                {
                    Console.WriteLine($"[BrowserHost] Download request forwarded successfully");
                }
                else
                {
                    Console.WriteLine($"[BrowserHost] Failed to forward download request: {response.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] SendDownloadRequest error: {ex.Message}");
            }
        }
    }

    static class Program
    {
        // Store current port for external access
        private static int _staticPort = 28900;

        public static int GetCurrentPort() => _staticPort;
        public static void SetCurrentPort(int port) => _staticPort = port;

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
            Console.WriteLine("[BrowserHost] 启动");

            // 创建 Job Object - 这是关键！确保进程终止时自动清理所有句柄
            IntPtr jobHandle = CreateJobObjectW(IntPtr.Zero, null);
            if (jobHandle != IntPtr.Zero)
            {
                // 设置 Job 限制：进程组的句柄关闭时自动终止进程
                var limitInfo = new JOBOBJECT_BASIC_LIMIT_INFORMATION();
                limitInfo.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

                // 将当前进程加入 Job Object
                IntPtr currentProcess = GetCurrentProcess();
                bool assigned = AssignProcessToJobObject(jobHandle, currentProcess);
                Console.WriteLine($"[BrowserHost] Job Object 创建: {assigned}");

                // 注意：不需要手动 CloseHandle(jobHandle)，进程退出时系统会自动清理
            }

            IntPtr parentHwnd = IntPtr.Zero;
            int initialWidth = 1280;
            int initialHeight = 720;
            int initialPort = 28900;  // 默认端口

            // 从命令行参数获取父窗口句柄和初始尺寸
            if (args.Length >= 1 && long.TryParse(args[0], out var parsedHwnd))
            {
                parentHwnd = new IntPtr(parsedHwnd);
                Console.WriteLine($"[BrowserHost] 父窗口句柄: {parentHwnd}");
            }

            if (args.Length >= 4)
            {
                if (int.TryParse(args[1], out var w))
                    initialWidth = w;
                if (int.TryParse(args[2], out var h))
                    initialHeight = h;
                if (int.TryParse(args[3], out var p))
                    initialPort = p;
                Console.WriteLine($"[BrowserHost] 初始尺寸: {initialWidth}x{initialHeight}, 端口: {initialPort}");
            }
            else if (args.Length >= 3)
            {
                if (int.TryParse(args[1], out var w))
                    initialWidth = w;
                if (int.TryParse(args[2], out var h))
                    initialHeight = h;
                Console.WriteLine($"[BrowserHost] 初始尺寸: {initialWidth}x{initialHeight}");
            }

            // 创建 WebView2 宿主
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

        private Microsoft.Web.WebView2.WinForms.WebView2? _webView;
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
        private const int TOGGLE_WIDTH_EXPANDED = 44;   // 展开后完整宽度
        private const int TOGGLE_WIDTH_COLLAPSED = 12;  // 常态露出12px在边缘
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

            Console.WriteLine("[BrowserHost] 创建容器窗体");
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
            _container.Closing += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] 容器正在关闭");
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
                        Console.WriteLine($"[BrowserHost] 从文件读取端口: {port}");
                        return port;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[BrowserHost] 读取端口文件失败: {ex.Message}");
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
                        Console.WriteLine($"[BrowserHost] 从备用路径读取端口: {port}");
                        return port;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[BrowserHost] 读取备用端口文件失败: {ex.Message}");
                }
            }

            Console.WriteLine($"[BrowserHost] 使用默认端口: {_defaultPort}");
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

        // 检测实际可用的端口
        private async Task<int> _detectAvailablePortAsync()
        {
            // 首先读取端口文件
            var filePort = _readPortFromFile();
            var portsToTry = new List<int> { filePort };
            portsToTry.AddRange(_backupPorts);

            foreach (var port in portsToTry)
            {
                try
                {
                    using var client = new System.Net.Http.HttpClient();
                    // 增加超时时间到 5 秒，给 Godot 更多响应时间
                    client.Timeout = TimeSpan.FromSeconds(5);
                    var response = await client.GetAsync($"http://localhost:{port}/api/health");
                    if (response.IsSuccessStatusCode)
                    {
                        Console.WriteLine($"[BrowserHost] 端口 {port} 可用");
                        return port;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[BrowserHost] 端口 {port} 不可用: {ex.Message}");
                }
            }

            // 如果都不可用，返回文件中的端口作为默认值
            Console.WriteLine($"[BrowserHost] 没有检测到可用端口，使用默认值: {filePort}");
            return filePort;
        }

        // 带超时限制的端口检测（用于导航操作，避免长时间等待）
        // 策略：直接使用文件中的端口，不做串行检测
        // 因为 LocalServer 一旦启动就会保持运行，端口不会变
        private Task<int> _detectAvailablePortWithTimeoutAsync()
        {
            var filePort = _readPortFromFile();
            Console.WriteLine($"[BrowserHost] 使用端口: {filePort}");
            return Task.FromResult(filePort);
        }

        private async void InitializeAsync()
        {
            try
            {
                Console.WriteLine("[BrowserHost] 开始初始化 WebView2");

                var userDataFolder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "STS2ModManager", "WebView2");

                Directory.CreateDirectory(userDataFolder);

                Console.WriteLine($"[BrowserHost] 用户数据目录: {userDataFolder}");

                var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                Console.WriteLine("[BrowserHost] 环境创建成功");

                _webView = new Microsoft.Web.WebView2.WinForms.WebView2();
                _webView.Dock = DockStyle.Fill;

                _container!.Controls.Add(_webView);
                _container!.FormBorderStyle = FormBorderStyle.None;
                _container!.WindowState = FormWindowState.Normal;
                _container!.BackColor = System.Drawing.Color.FromArgb(20, 20, 20);

                await Task.Delay(200);

                await _webView.EnsureCoreWebView2Async(env);
                Console.WriteLine("[BrowserHost] CoreWebView2 初始化成功");

                _webView.CoreWebView2.Settings.AreDevToolsEnabled = true;
                _webView.CoreWebView2.Settings.IsScriptEnabled = true;
                _webView.CoreWebView2.Settings.IsWebMessageEnabled = true;
                _webView.CoreWebView2.Settings.IsStatusBarEnabled = false;

                // 注意：AddHostObjectToScript 不能在 Navigate 之前调用，必须在页面加载后
                // 所以在 NavigationCompleted 中注册（见下方）

                _webView.NavigationStarting += (s, e) =>
                {
                    Console.WriteLine($"[BrowserHost] 导航开始: {e.Uri}");

                    // 取消任何挂起的请求，防止线程池饥饿
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
                    Console.WriteLine($"[BrowserHost] 导航完成: 成功={e.IsSuccess}, HTTP={e.HttpStatusCode}, URL={currentUrl}");

                    // 如果是 Nexus Mods 页面，不管成功失败都不进行本地重试
                    if (currentUrl.Contains("nexusmods.com"))
                    {
                        if (!e.IsSuccess)
                        {
                            Console.WriteLine($"[BrowserHost] Nexus 页面加载失败: {e.WebErrorStatus}");
                            // 不执行任何重试，保持错误页面显示
                        }
                        return; // 跳过本地页面的 HostObject 注册逻辑
                    }

                    if (!e.IsSuccess)
                    {
                        Console.WriteLine($"[BrowserHost] 错误: {e.WebErrorStatus}");
                        // 只在首次失败时重试一次
                        if (_retryCount == 0)
                        {
                            _retryCount = 1;
                            // 重试时使用 hash URL，让 WebUI 正确切换到模组页
                            var retryUrl = $"http://localhost:{_currentPort}/index.html#mods";
                            Console.WriteLine($"[BrowserHost] 重试导航到: {retryUrl}");
                            // 重试前取消所有挂起请求
                            Program.CancelPendingRequests();
                            Thread.Sleep(300);
                            _webView.CoreWebView2.Navigate(retryUrl);
                        }
                        else
                        {
                            Console.WriteLine($"[BrowserHost] 重试也失败，放弃");
                            // 不再显示 MessageBox，避免阻塞 UI
                            // 用户可以通过抽屉菜单的返回首页按钮重试
                        }
                    }
                    else
                    {
                        Console.WriteLine($"[BrowserHost] 成功连接到端口 {_currentPort}");
                        // 创建 BrowserHostObject 并设置更新弹窗回调
                        var browserHostObj = new BrowserHostObject();
                        browserHostObj.SetUpdateDialogCallback((currentVer, newVer, changelog, downloadUrl) =>
                        {
                            Console.WriteLine($"[BrowserHost] 显示更新弹窗: {currentVer} -> {newVer}");
                            ShowUpdateDialog(currentVer, newVer, changelog, downloadUrl);
                        });

                        // 设置导航回调
                        browserHostObj.SetNavigateCallback((url) =>
                        {
                            Console.WriteLine($"[BrowserHost] Navigate callback: {url}");
                            if (_webView?.CoreWebView2 != null)
                            {
                                _webView.CoreWebView2.Navigate(url);
                            }
                        });

                        // 导航成功后注册 Host Object（必须在页面加载后）
                        try
                        {
                            _webView.CoreWebView2.AddHostObjectToScript("browserHost", browserHostObj);
                            Console.WriteLine("[BrowserHost] AddHostObjectToScript 已注册");
                        }
                        catch (Exception ex2)
                        {
                            Console.WriteLine($"[BrowserHost] AddHostObjectToScript 注册失败: {ex2.Message}");
                            Console.WriteLine($"[BrowserHost] ex2 type: {ex2.GetType().FullName}");
                        }
                    }
                };

                _webView.CoreWebView2.NewWindowRequested += (s, e) =>
                {
                    Console.WriteLine($"[BrowserHost] 新窗口请求: {e.Uri}");
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

                    // 等待页面完全加载（包括动态内容）
                    await Task.Delay(2000);

                    await InjectExtensionScriptAsync();
                };

                // 监听 URL 变化（SPA 导航）
                string lastInjectedUrl = "";
                _webView.CoreWebView2.SourceChanged += async (s, e) =>
                {
                    var currentUrl = _webView.CoreWebView2.Source;
                    if (string.IsNullOrEmpty(currentUrl) || !currentUrl.Contains("nexusmods.com"))
                        return;

                    // 避免重复注入同一页面
                    if (currentUrl == lastInjectedUrl)
                        return;

                    Console.WriteLine($"[BrowserHost] Nexus URL changed to: {currentUrl}");
                    lastInjectedUrl = currentUrl;

                    // 等待页面内容更新
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

                            // 延迟后检查脚本是否成功运行
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
                Console.WriteLine($"[BrowserHost] 导航到: http://localhost:{_currentPort}/index.html");
                Console.WriteLine($"[BrowserHost] NavigationCompleted handler 已注册，等待页面加载...");
                Console.WriteLine($"[BrowserHost] _webView.CoreWebView2 对象: {_webView.CoreWebView2 != null}");

                // 延迟 3 秒后检查 Host Objects 是否注入（用于调试）
                await Task.Delay(3000);
                Console.WriteLine($"[BrowserHost] 延迟检查完成");

                // 诊断：检查 Host Object 是否在 JavaScript 中可用
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
                    Console.WriteLine($"[BrowserHost] Host Object 诊断: {result}");
                }
                catch (Exception diagEx)
                {
                    Console.WriteLine($"[BrowserHost] Host Object 诊断失败: {diagEx.Message}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] 初始化失败: {ex.Message}");
                MessageBox.Show($"WebView2 初始化失败: {ex.Message}", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void EmbedToParent()
        {
            if (_parentHwnd == IntPtr.Zero || _webView == null || _container == null) return;

            try
            {
                IntPtr containerHwnd = _container.Handle;
                Console.WriteLine($"[BrowserHost] 容器句柄: {containerHwnd}");

                if (containerHwnd == IntPtr.Zero)
                {
                    Console.WriteLine("[BrowserHost] 容器句柄为 0，等待...");
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

                // 先设置窗口大小
                UpdateContainerSize();

                // 再 SetParent
                var result = SetParent(containerHwnd, _parentHwnd);
                Console.WriteLine($"[BrowserHost] SetParent 结果: {result}");

                // 清除 WS_EX_CLIENTEDGE 扩展样式（这会导致内容区向内缩进）
                int exStyle = NativeMethods.GetWindowLong(containerHwnd, -20); // GWL_EXSTYLE = -20
                if ((exStyle & 0x200) != 0) // WS_EX_CLIENTEDGE = 0x200
                {
                    NativeMethods.SetWindowLong(containerHwnd, -20, exStyle & ~0x200);
                    DebugLog($"[EmbedToParent] 清除 WS_EX_CLIENTEDGE, 原样式={exStyle}");
                    // 让窗口重新应用样式
                    SetWindowPos(containerHwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0040 | 0x0001); // SWP_FRAMECHANGED | SWP_NOACTIVATE
                }

                ShowWindow(containerHwnd, SW_SHOW);
                if (_webView != null)
                {
                    _webView.Visible = true;
                    _webView.BringToFront();
                }

                // 定期更新位置和大小
                _resizeTimer = new System.Windows.Forms.Timer();
                _resizeTimer.Interval = 100;
                _resizeTimer.Tick += (s, e) => UpdateContainerSize();
                _resizeTimer.Start();

                Console.WriteLine("[BrowserHost] 容器嵌入完成");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] 嵌入失败: {ex.Message}");
            }
        }

        private void UpdateContainerSize()
        {
            if (_parentHwnd == IntPtr.Zero || _container == null) return;

            try
            {
                RECT parentRect;
                if (!GetWindowRect(_parentHwnd, out parentRect))
                {
                    DebugLog($"[UpdateContainerSize] GetWindowRect 失败");
                    return;
                }

                int parentWidth = parentRect.Right - parentRect.Left;
                int parentHeight = parentRect.Bottom - parentRect.Top;

                
                if (parentWidth == _lastParentWidth && parentHeight == _lastParentHeight)
                    return;

                _lastParentWidth = parentWidth;
                _lastParentHeight = parentHeight;

                Console.WriteLine($"[BrowserHost] 父窗口尺寸: {parentWidth}x{parentHeight}");

                // 子窗口位置相对于父窗口客户区
                SetWindowPos(_container.Handle, IntPtr.Zero, 0, 0, parentWidth, parentHeight,
                    SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW);

                _container!.Width = parentWidth;
                _container!.Height = parentHeight;

                if (_webView != null)
                {
                    _webView.Width = parentWidth;
                    _webView.Height = parentHeight;
                }

                Console.WriteLine($"[BrowserHost] 容器已调整: {_container!.Width}x{_container!.Height}");

                UpdateToggleButton();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BrowserHost] 调整大小失败: {ex.Message}");
            }
        }

        private void CreateToggleButton()
        {
                        if (_container == null) return;

            // 创建抽屉面板（默认折叠在左侧）
            _drawerPanel = new Panel();
            _drawerPanel.Name = "DrawerPanel";
            _drawerPanel.Size = new System.Drawing.Size(DRAWER_WIDTH, _container.Height);
            _drawerPanel.Location = new System.Drawing.Point(-DRAWER_WIDTH, 0);
            _drawerPanel.BackColor = System.Drawing.Color.FromArgb(20, 25, 35);
            _drawerPanel.AutoScroll = false;
            _drawerPanel.Padding = new Padding(0);
            _drawerPanel.Margin = new Padding(0);
            _drawerPanel.BorderStyle = BorderStyle.None;

            // 创建抽屉内容容器
            var drawerContent = new VStackPanel();
            drawerContent.Name = "DrawerContent";
            drawerContent.Dock = DockStyle.Fill;
            drawerContent.BackColor = Color.Transparent;
            _drawerPanel.Controls.Add(drawerContent);

            // 创建返回首页按钮
            var homeBtn = new DrawerMenuButton("⌂ 首页", 44);
            homeBtn.Dock = DockStyle.Top;
            homeBtn.Click += async (s, e) =>
            {
                Console.WriteLine("[BrowserHost] 抽屉菜单: 返回首页");
                if (_webView?.CoreWebView2 != null)
                {
                    // 取消任何挂起的请求，防止线程池饥饿
                    Program.CancelPendingRequests();

                    // 检测实际可用的端口（带超时限制）
                    var availablePort = await _detectAvailablePortWithTimeoutAsync();
                    Console.WriteLine($"[BrowserHost] 返回首页，检测到可用端口: {availablePort}");
                    // 使用 hash 路由 #mods，服务器返回 index.html，JavaScript 检测 hash 切换页面
                    _webView.CoreWebView2.Navigate($"http://localhost:{availablePort}/index.html#mods");
                }
                CloseDrawer();
            };
            drawerContent.Controls.Add(homeBtn);

            // 创建刷新页面按钮
            var refreshBtn = new DrawerMenuButton("↻ 刷新", 44);
            refreshBtn.Dock = DockStyle.Top;
            refreshBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] 抽屉菜单: 刷新页面");
                if (_webView?.CoreWebView2 != null)
                {
                    _webView.CoreWebView2.Reload();
                    Console.WriteLine("[BrowserHost] 页面已刷新");
                }
                CloseDrawer();
            };
            drawerContent.Controls.Add(refreshBtn);

            // 创建配置页面
            var configPage = new ConfigPage();
            configPage.Visible = false;
            configPage.Dock = DockStyle.Fill;
            drawerContent.Controls.Add(configPage);

            // 创建配置按钮
            var configBtn = new DrawerMenuButton("⚙ 配置", 44);
            configBtn.Dock = DockStyle.Top;
            configBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] 抽屉菜单: 配置");
                // 隐藏菜单，显示配置页面
                foreach (Control c in drawerContent.Controls)
                {
                    c.Visible = false;
                }
                configPage.Visible = true;
                configPage.BringToFront();
            };
            drawerContent.Controls.Add(configBtn);

            // 配置文件页面，用于返回菜单
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

            // 保存端口
            configPage.OnSavePort += (port) =>
            {
                _updatePort(port);
                MessageBox.Show("端口已保存，需要重启应用程序才能生效。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };

            // 重启服务
            configPage.OnRestartService += () =>
            {
                Console.WriteLine("[BrowserHost] 重启本地服务...");
                // 重新导航到当前端口刷新连接
                if (_webView?.CoreWebView2 != null)
                {
                    _webView.CoreWebView2.Navigate($"http://localhost:{_currentPort}/index.html");
                }
                MessageBox.Show("服务已重启。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };

            // 清除缓存并刷新
            configPage.OnClearCache += () =>
            {
                Console.WriteLine("[BrowserHost] 清除缓存并刷新...");
                if (_webView?.CoreWebView2 != null)
                {
                    _webView.CoreWebView2.Navigate($"http://localhost:{_currentPort}/index.html");
                }
                MessageBox.Show("缓存已清除，页面已刷新。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };

            // 检查更新 - 直接调用 API 并处理结果，与原版 STS2Settings.checkForUpdates 流程一致
            configPage.OnCheckUpdates += () =>
            {
                Console.WriteLine("[BrowserHost] 检查更新...");
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

            // 创建分隔线
            var sep1 = new Panel();
            sep1.Name = "Sep1";
            sep1.Size = new System.Drawing.Size(DRAWER_WIDTH - 20, 1);
            sep1.BackColor = System.Drawing.Color.FromArgb(60, 70, 90);
            sep1.Dock = DockStyle.Top;
            sep1.Margin = new Padding(10, 10, 10, 0);
            drawerContent.Controls.Add(sep1);

            // 创建启动原版按钮
            var vanillaBtn = new DrawerMenuButton("▶ 启动原版", 44);
            vanillaBtn.Dock = DockStyle.Top;
            vanillaBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] 抽屉菜单: 启动原版");
                System.Diagnostics.Process.Start("steam://launch/2868840");
                CloseDrawer();
            };
            drawerContent.Controls.Add(vanillaBtn);

            // 创建启动模组版按钮
            var moddedBtn = new DrawerMenuButton("▶ 启动模组版", 44);
            moddedBtn.Dock = DockStyle.Top;
            moddedBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] 抽屉菜单: 启动模组版");
                System.Diagnostics.Process.Start("steam://launch/2868840/dialog");
                CloseDrawer();
            };
            drawerContent.Controls.Add(moddedBtn);

            // 创建分隔线
            var sep2 = new Panel();
            sep2.Name = "Sep2";
            sep2.Size = new System.Drawing.Size(DRAWER_WIDTH - 20, 1);
            sep2.BackColor = System.Drawing.Color.FromArgb(60, 70, 90);
            sep2.Dock = DockStyle.Top;
            sep2.Margin = new Padding(10, 10, 10, 0);
            drawerContent.Controls.Add(sep2);

            // 创建退出按钮
            var exitBtn = new DrawerMenuButton("✕ 退出", 44);
            exitBtn.Dock = DockStyle.Top;
            exitBtn.Click += (s, e) =>
            {
                Console.WriteLine("[BrowserHost] 抽屉菜单: 退出");
                Environment.Exit(0);
            };
            drawerContent.Controls.Add(exitBtn);

            _container.Controls.Add(_drawerPanel);
            _drawerPanel.BringToFront();

            // 创建 Toggle 按钮
            _toggleBtn = new ToggleButton();
            _toggleBtn.Name = "ToggleDrawer";
            _toggleBtn.Size = new System.Drawing.Size(TOGGLE_WIDTH_COLLAPSED, TOGGLE_HEIGHT);
            _toggleBtn.Location = new System.Drawing.Point(0, (_container.Height - TOGGLE_HEIGHT) / 2);

            _container.Controls.Add(_toggleBtn);
            _toggleBtn.BringToFront();

            // 鼠标离开时延迟收缩
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

            // 启动定时器轮询检测鼠标位置
            _mouseCheckTimer = new System.Windows.Forms.Timer();
            _mouseCheckTimer.Interval = 50;  // 每 50ms 检测一次
            _mouseCheckTimer.Tick += (s, e) => OnMouseCheckTick();
            _mouseCheckTimer.Start();

            Console.WriteLine("[BrowserHost] DrawerToggleButton 已创建");
        }

        private void OnMouseCheckTick()
        {
            if (_toggleBtn == null || _container == null) return;

            // 抽屉展开时，不处理悬停逻辑
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
            // 限制圆角半径
            radius = Math.Min(radius, rect.Width / 2 - 1);
            // 宽度太小时不画圆角，直接用矩形
            if (radius <= 1 || rect.Width <= 8)
            {
                path.AddRectangle(rect);
                return path;
            }
            int diameter = radius * 2;
            int right = rect.Right;
            int bottom = rect.Bottom;

            // 从顶边开始，顺时针绘制
            path.AddLine(rect.Left, rect.Top + radius, right - radius, rect.Top);  // 上边
            path.AddArc(right - diameter, rect.Top, diameter, diameter, 270, 90);   // 右上圆角
            path.AddArc(right - diameter, bottom - diameter, diameter, diameter, 0, 90); // 右下圆角
            path.AddLine(rect.Left, bottom, right - radius, bottom);                // 下边
            path.AddLine(rect.Left, bottom, rect.Left, rect.Top + radius);              // 左边（直角）
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
            // 确保抽屉面板可见
            if (_drawerPanel != null)
            {
                _drawerPanel.Visible = true;
                Console.WriteLine("[BrowserHost] OpenDrawer: DrawerPanel 已显示");
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

                // ToggleButton 跟随移动
                if (_toggleBtn != null)
                {
                    int btnNewX = newX + DRAWER_WIDTH;
                    _toggleBtn.Location = new System.Drawing.Point(btnNewX, _toggleBtn.Location.Y);
                }

                if (step >= ANIM_STEPS)
                {
                    tween.Stop();
                    _isAnimating = false;
                    // 动画结束，按钮跟随到抽屉右边
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

                // ToggleButton 跟随抽屉移动（保持相对位置）
                if (_toggleBtn != null)
                {
                    int btnNewX = newX + DRAWER_WIDTH;
                    _toggleBtn.Location = new System.Drawing.Point(btnNewX, _toggleBtn.Location.Y);
                }

                if (step >= ANIM_STEPS)
                {
                    tween.Stop();
                    _isAnimating = false;
                    // 动画结束后隐藏抽屉面板，避免阴影残留
                    if (_drawerPanel != null)
                    {
                        _drawerPanel.Visible = false;
                        Console.WriteLine("[BrowserHost] CloseDrawer: DrawerPanel 已隐藏");
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

            // 按钮放在容器左边缘，垂直居中
            _toggleBtn.Location = new System.Drawing.Point(0, (_container.Height - TOGGLE_HEIGHT) / 2);
            _toggleBtn.BringToFront();
        }

        [DllImport("user32.dll")]
        private static extern bool DestroyMenu(IntPtr hMenu);

        // 显示更新弹窗 - 在容器内显示覆盖层
        private void ShowUpdateDialog(string currentVersion, string newVersion, string changelog, string downloadUrl)
        {
            Console.WriteLine($"[BrowserHost] ShowUpdateDialog called: current={currentVersion}, new={newVersion}");

            if (_container == null) return;

            // 保存 ToggleButton 引用，供弹窗关闭后恢复
            var toggleBtnRef = _toggleBtn;
            if (toggleBtnRef != null)
            {
                toggleBtnRef.Visible = false;
                Console.WriteLine("[BrowserHost] 隐藏 ToggleButton");
            }

            // 在主线程创建和显示面板
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
            // 显示弹窗时先关闭抽屉并完全隐藏，避免背景干扰
            CloseDrawer();
            // 完全隐藏抽屉面板，避免阴影显示
            if (_drawerPanel != null)
            {
                _drawerPanel.Visible = false;
                Console.WriteLine("[BrowserHost] 隐藏 DrawerPanel");
            }

            // 清理所有已存在的更新弹窗（防止重复添加）
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
                    Console.WriteLine("[BrowserHost] 移除旧弹窗: " + c.Name);
                }
            }
            _updateDialogPanel = null;

            // 创建新的更新弹窗面板
            _updateDialogPanel = new UpdateDialogPanel(currentVersion, newVersion, changelog);
            _updateDialogPanel.OnUpdateNow += () =>
            {
                Console.WriteLine("[BrowserHost] 用户选择立即更新，调用Godot下载更新");
                // 调用Web API触发Godot下载更新
                if (_webView?.CoreWebView2 != null)
                {
                    var script = $@"
                        (async () => {{
                            try {{
                                const result = await window.api.downloadUpdate('{downloadUrl.Replace("'", "\\'")}');
                                console.log('[BrowserHost] 下载更新API返回:', result);
                            }} catch(e) {{
                                console.error('[BrowserHost] 调用下载更新API失败:', e.message);
                            }}
                        }})()
                    ";
                    _webView.CoreWebView2.ExecuteScriptAsync(script);
                }
                else
                {
                    Console.WriteLine("[BrowserHost] WebView2未就绪，无法调用下载API");
                }
                // 关闭弹窗并清理
                if (_updateDialogPanel != null)
                {
                    _updateDialogPanel.Visible = false;
                    _container.Controls.Remove(_updateDialogPanel);
                    _updateDialogPanel.Dispose();
                    _updateDialogPanel = null;
                    Console.WriteLine("[BrowserHost] 更新弹窗已关闭并清理");
                }
                // 恢复 ToggleButton
                if (toggleBtnRef != null) toggleBtnRef.Visible = true;
            };
            _updateDialogPanel.OnLater += () =>
            {
                Console.WriteLine("[BrowserHost] 用户选择稍后更新");
                // 关闭弹窗并清理
                if (_updateDialogPanel != null)
                {
                    _updateDialogPanel.Visible = false;
                    _container.Controls.Remove(_updateDialogPanel);
                    _updateDialogPanel.Dispose();
                    _updateDialogPanel = null;
                    Console.WriteLine("[BrowserHost] 更新弹窗已关闭并清理");
                }
                // 恢复 ToggleButton
                if (toggleBtnRef != null) toggleBtnRef.Visible = true;
            };

            // 添加到容器并显示
            _container.Controls.Add(_updateDialogPanel);
            _updateDialogPanel.BringToFront();
            _updateDialogPanel.ShowWithAnimation();

            Console.WriteLine("[BrowserHost] UpdateDialogPanel 已显示");
        }

        // 配置页面 - 在抽屉内显示多页配置
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

                // 返回按钮
                _backBtn = new Button();
                _backBtn.Text = "← 返回";
                _backBtn.Size = new Size(80, 32);
                _backBtn.Location = new Point(10, 10);
                _backBtn.FlatStyle = FlatStyle.Flat;
                _backBtn.BackColor = Color.FromArgb(30, 40, 55);
                _backBtn.ForeColor = Color.FromArgb(180, 185, 200);
                _backBtn.Cursor = Cursors.Hand;
                _backBtn.Click += (s, e) => OnBack?.Invoke();
                this.Controls.Add(_backBtn);

                // 标题
                _titleLabel = new Label();
                _titleLabel.Text = "管理器配置";
                _titleLabel.Font = new Font("Segoe UI", 12f, FontStyle.Bold);
                _titleLabel.ForeColor = Color.FromArgb(200, 220, 240);
                _titleLabel.Location = new Point(10, 60);
                _titleLabel.AutoSize = true;
                this.Controls.Add(_titleLabel);

                // 端口设置
                _portLabel = new Label();
                _portLabel.Text = "端口:";
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
                _saveBtn.Text = "保存";
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
                        Console.WriteLine($"[BrowserHost] 保存端口: {port}");
                        OnSavePort?.Invoke(port);
                    }
                    else
                    {
                        Console.WriteLine($"[BrowserHost] 无效端口: {_portInput.Text}");
                    }
                };
                this.Controls.Add(_saveBtn);

                // 版本信息
                _versionLabel = new Label();
                _versionLabel.Text = "当前版本: v1.0.0";
                _versionLabel.Font = new Font("Segoe UI", 10f);
                _versionLabel.ForeColor = Color.FromArgb(150, 155, 170);
                _versionLabel.Location = new Point(10, 160);
                _versionLabel.AutoSize = true;
                this.Controls.Add(_versionLabel);

                // 重启服务按钮
                _restartBtn = new Button();
                _restartBtn.Text = "重启服务";
                _restartBtn.Size = new Size(110, 32);
                _restartBtn.Location = new Point(10, 210);
                _restartBtn.FlatStyle = FlatStyle.Flat;
                _restartBtn.BackColor = Color.FromArgb(30, 40, 55);
                _restartBtn.ForeColor = Color.FromArgb(180, 185, 200);
                _restartBtn.Cursor = Cursors.Hand;
                _restartBtn.Click += (s, e) =>
                {
                    Console.WriteLine("[BrowserHost] 重启服务");
                    OnRestartService?.Invoke();
                };
                this.Controls.Add(_restartBtn);

                // 清除缓存并刷新按钮
                _clearCacheBtn = new Button();
                _clearCacheBtn.Text = "清除缓存并刷新";
                _clearCacheBtn.Size = new Size(130, 32);
                _clearCacheBtn.Location = new Point(130, 210);
                _clearCacheBtn.FlatStyle = FlatStyle.Flat;
                _clearCacheBtn.BackColor = Color.FromArgb(30, 40, 55);
                _clearCacheBtn.ForeColor = Color.FromArgb(180, 185, 200);
                _clearCacheBtn.Cursor = Cursors.Hand;
                _clearCacheBtn.Click += (s, e) =>
                {
                    Console.WriteLine("[BrowserHost] 清除缓存并刷新");
                    OnClearCache?.Invoke();
                };
                this.Controls.Add(_clearCacheBtn);

                // 检查更新按钮
                _checkUpdateBtn = new Button();
                _checkUpdateBtn.Text = "检查更新";
                _checkUpdateBtn.Size = new Size(110, 32);
                _checkUpdateBtn.Location = new Point(10, 260);
                _checkUpdateBtn.FlatStyle = FlatStyle.Flat;
                _checkUpdateBtn.BackColor = Color.FromArgb(30, 40, 55);
                _checkUpdateBtn.ForeColor = Color.FromArgb(180, 185, 200);
                _checkUpdateBtn.Cursor = Cursors.Hand;
                _checkUpdateBtn.Click += (s, e) =>
                {
                    Console.WriteLine("[BrowserHost] 检查更新");
                    OnCheckUpdates?.Invoke();
                };
                this.Controls.Add(_checkUpdateBtn);

                // 更新状态标签
                _updateStatusLabel = new Label();
                _updateStatusLabel.Text = "";
                _updateStatusLabel.Font = new Font("Segoe UI", 9f);
                _updateStatusLabel.ForeColor = Color.FromArgb(150, 155, 170);
                _updateStatusLabel.Location = new Point(130, 268);
                _updateStatusLabel.AutoSize = true;
                this.Controls.Add(_updateStatusLabel);
            }

            // 设置更新状态文本
            public void SetUpdateStatus(string status)
            {
                _updateStatusLabel.Text = status;
            }

            // 重置页面状态
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

        // 抽屉菜单按钮 - WebUI 风格
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

                // 背景
                using (var bgBrush = new SolidBrush(this.BackColor))
                {
                    g.FillRectangle(bgBrush, 0, 0, Width, Height);
                }

                // 左边高亮条（悬停时显示蓝色指示条）
                if (_isHovered)
                {
                    using (var indicatorBrush = new SolidBrush(Color.FromArgb(100, 192, 250)))
                    {
                        g.FillRectangle(indicatorBrush, 0, 0, 3, Height);
                    }
                }

                // 文字
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

        // 垂直堆叠面板（用于抽屉内容）
        class VStackPanel : Panel
        {
            public VStackPanel()
            {
                this.Dock = DockStyle.Fill;
                this.BackColor = Color.FromArgb(20, 25, 35);
            }
        }

        // 自定义 ToggleButton - 简化版本，避免渲染错误
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

                // 用路径作为裁剪区域，防止 WinForms 在路径外绘制背景
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

        // 更新弹窗面板 - 简化版本，无动画，避免渲染问题
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

                // 面板配置 - 填充整个容器
                this.Name = "UpdateDialogPanel";
                this.Dock = DockStyle.Fill;
                this.BackColor = Color.FromArgb(22, 28, 38);
                this.Padding = new Padding(0);
                this.Margin = new Padding(0);
                this.Visible = false;

                // 创建中央内容面板（卡片样式）
                var cardPanel = new Panel();
                cardPanel.Name = "CardPanel";
                cardPanel.Size = new Size(440, 380);
                cardPanel.BackColor = Color.FromArgb(35, 42, 55);
                cardPanel.BorderStyle = BorderStyle.None;

                // 顶部装饰条
                var headerBar = new Panel();
                headerBar.Size = new Size(440, 4);
                headerBar.Location = new Point(0, 0);
                headerBar.BackColor = Color.FromArgb(60, 130, 200);
                cardPanel.Controls.Add(headerBar);

                // 图标和标题区域
                var iconPanel = new Panel();
                iconPanel.Size = new Size(440, 60);
                iconPanel.Location = new Point(0, 20);
                iconPanel.BackColor = Color.Transparent;
                cardPanel.Controls.Add(iconPanel);

                // 下载图标（用 Label 模拟）
                var iconLabel = new Label();
                iconLabel.Text = "⬇";
                iconLabel.Font = new Font("Segoe UI", 28f, FontStyle.Regular);
                iconLabel.ForeColor = Color.FromArgb(60, 130, 200);
                iconLabel.Location = new Point(25, 0);
                iconLabel.AutoSize = true;
                iconPanel.Controls.Add(iconLabel);

                // 顶部标题栏
                var titleLabel = new Label();
                titleLabel.Name = "TitleLabel";
                titleLabel.Text = "发现新版本";
                titleLabel.Font = new Font("Segoe UI", 18f, FontStyle.Bold);
                titleLabel.ForeColor = Color.FromArgb(220, 230, 245);
                titleLabel.Location = new Point(70, 8);
                titleLabel.AutoSize = true;
                iconPanel.Controls.Add(titleLabel);

                // 版本信息标签
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

                // 当前版本信息
                var currentVersionLabel = new Label();
                currentVersionLabel.Text = $"当前版本: {_currentVersion}";
                currentVersionLabel.Font = new Font("Segoe UI", 9f);
                currentVersionLabel.ForeColor = Color.FromArgb(140, 150, 165);
                currentVersionLabel.Location = new Point(25, 90);
                currentVersionLabel.AutoSize = true;
                cardPanel.Controls.Add(currentVersionLabel);

                // 分隔线
                var sep = new Panel();
                sep.Size = new Size(390, 1);
                sep.Location = new Point(25, 115);
                sep.BackColor = Color.FromArgb(70, 80, 100);
                cardPanel.Controls.Add(sep);

                // 更新内容标题
                var changelogTitle = new Label();
                changelogTitle.Text = "更新内容";
                changelogTitle.Font = new Font("Segoe UI", 11f, FontStyle.Bold);
                changelogTitle.ForeColor = Color.FromArgb(200, 210, 225);
                changelogTitle.Location = new Point(25, 125);
                changelogTitle.AutoSize = true;
                cardPanel.Controls.Add(changelogTitle);

                // 更新日志内容
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

                // 按钮区域背景
                var buttonPanelBg = new Panel();
                buttonPanelBg.Size = new Size(440, 65);
                buttonPanelBg.Location = new Point(0, 315);
                buttonPanelBg.BackColor = Color.FromArgb(30, 38, 50);
                cardPanel.Controls.Add(buttonPanelBg);

                // 按钮区域
                var buttonPanel = new Panel();
                buttonPanel.Size = new Size(390, 45);
                buttonPanel.Location = new Point(25, 10);
                buttonPanel.BackColor = Color.Transparent;
                buttonPanelBg.Controls.Add(buttonPanel);

                // 稍后更新按钮
                var laterBtn = new Button();
                laterBtn.Name = "LaterBtn";
                laterBtn.Text = "稍后更新";
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
                    Console.WriteLine("[UpdateDialogPanel] 稍后更新 clicked");
                    OnLater?.Invoke();
                    this.Visible = false;
                };
                buttonPanel.Controls.Add(laterBtn);

                // 立即更新按钮
                var updateBtn = new Button();
                updateBtn.Name = "UpdateBtn";
                updateBtn.Text = "立即更新";
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
                    Console.WriteLine("[UpdateDialogPanel] 立即更新 clicked");
                    OnUpdateNow?.Invoke();
                    // 延迟隐藏，让事件先处理完
                    this.Visible = false;
                };
                buttonPanel.Controls.Add(updateBtn);

                // 将卡片面板添加到中央
                this.Controls.Add(cardPanel);
                this.Resize += (s, e) =>
                {
                    int x = (this.Width - cardPanel.Width) / 2;
                    int y = (this.Height - cardPanel.Height) / 2;
                    cardPanel.Location = new Point(Math.Max(0, x), Math.Max(0, y));
                };
                // 初始居中
                cardPanel.Location = new Point((this.Width - cardPanel.Width) / 2, (this.Height - cardPanel.Height) / 2);

                // 点击背景关闭
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
                    return "暂无更新说明";

                var lines = changelog.Split('\n');
                var result = new System.Text.StringBuilder();
                foreach (var line in lines)
                {
                    var trimmed = line.Trim();
                    if (trimmed.StartsWith("- ") || trimmed.StartsWith("* "))
                    {
                        result.AppendLine("• " + trimmed.Substring(2));
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
                // 无动画，直接显示
                this.Visible = true;
                this.BringToFront();

                // 居中卡片
                var card = this.Controls["CardPanel"];
                if (card != null)
                {
                    int x = (this.Width - card.Width) / 2;
                    int y = (this.Height - card.Height) / 2;
                    card.Location = new Point(Math.Max(0, x), Math.Max(0, y));
                }
                Console.WriteLine("[UpdateDialogPanel] 已显示");
            }

            public void HideWithAnimation()
            {
                // 无动画，直接隐藏
                this.Visible = false;
                Console.WriteLine("[UpdateDialogPanel] 已隐藏");
            }
        }
    }
}
