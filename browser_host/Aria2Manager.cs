using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace BrowserHost
{
    /// <summary>
    /// Aria2 下载管理器 - 通过 RPC 接口控制 Aria2 进程
    /// </summary>
    public class Aria2Manager
    {
        private Process? _aria2Process;
        private HttpClient _httpClient;
        private string _rpcUrl = "http://localhost:6800/jsonrpc";
        private string _rpcToken = "sts2-mod-manager";
        private bool _isRunning = false;
        private readonly object _lock = new object();

        // Aria2 默认路径
        private static readonly string[] _defaultAria2Paths = {
            ".\\aria2c.exe",
            "E:\\modmanager_project\\sts-2-modmanager\\browser_host\\publish\\aria2c.exe",
            "C:\\aria2\\aria2c.exe",
            "C:\\Program Files\\aria2\\aria2c.exe"
        };

        // 下载任务状态缓存
        private Dictionary<string, Aria2Download> _activeDownloads = new();     

        public bool IsRunning => _isRunning;

        public event EventHandler<Aria2Download>? DownloadComplete;
        public event EventHandler<Aria2Download>? DownloadError;
        public event EventHandler<(string Gid, int Progress, long Speed)>? ProgressChanged;

        public Aria2Manager()
        {
            _httpClient = new HttpClient();
            _httpClient.Timeout = TimeSpan.FromSeconds(30);
        }

        // 获取进程路径
        [System.Runtime.InteropServices.DllImport("psapi.dll")]
        private static extern uint GetModuleFileNameEx(IntPtr hProcess, IntPtr hModule, System.Text.StringBuilder lpFilename, int nSize);

        private static string GetProcessPath(int pid)
        {
            try
            {
                var process = System.Diagnostics.Process.GetProcessById(pid);   
                return process.MainModule?.FileName ?? "unknown";
            }
            catch
            {
                return "access denied";
            }
        }

        /// <summary>
        /// 启动 Aria2 RPC 服务器
        /// </summary>
        public bool Start(string aria2Path, int rpcPort = 6800)
        {
            lock (_lock)
            {
                if (_isRunning) return true;

                try
                {
                    // 诊断日志
                    Console.WriteLine($"[Aria2Manager] Start called with path: {aria2Path}");
                    Console.WriteLine($"[Aria2Manager] File exists: {System.IO.File.Exists(aria2Path)}");
                    Console.WriteLine($"[Aria2Manager] BaseDirectory: {AppDomain.CurrentDomain.BaseDirectory}");

                    // 如果 aria2c.exe 不存在，打印错误并返回
                    if (!System.IO.File.Exists(aria2Path))
                    {
                        Console.WriteLine($"[Aria2Manager] ERROR: aria2c.exe not found at: {aria2Path}");
                        Console.WriteLine($"[Aria2Manager] Please copy aria2c.exe to this directory.");
                        return false;
                    }

                    // 检查是否已有正常的 aria2c 进程在运行
                    var existingProcesses = System.Diagnostics.Process.GetProcessesByName("aria2c");
                    Console.WriteLine($"[Aria2Manager] Existing aria2c processes: {existingProcesses.Length}");

                    if (existingProcesses.Length > 0)
                    {
                        // 检查是否有进程已经在监听 RPC 端口
                        bool hasRunningAria2 = false;
                        foreach (var p in existingProcesses)
                        {
                            try
                            {
                                // 简单检查进程是否还在运行
                                if (!p.HasExited)
                                {
                                    Console.WriteLine($"[Aria2Manager] Found running aria2c: PID={p.Id}");
                                    hasRunningAria2 = true;
                                    // 直接返回 true，使用现有的进程
                                    _isRunning = true;
                                    _ = PollStatusAsync();
                                    return true;
                                }
                            }
                            catch { }
                        }

                        if (hasRunningAria2)
                        {
                            Console.WriteLine($"[Aria2Manager] Using existing aria2c process");
                            return true;
                        }
                    }

                    // 构建启动参数（简化版，避免重定向导致的问题）
                    var args = new List<string>
                    {
                        "--enable-rpc",
                        $"--rpc-listen-port={rpcPort}",
                        "--rpc-listen-all",  // 不带 =true
                        $"--rpc-secret={_rpcToken}",
                        "--disable-ipv6=true",  // 禁用 IPv6
                        "--check-certificate=false",
                        "--quiet",  // 静默模式，不输出到控制台
                    };

                    var startInfo = new ProcessStartInfo
                    {
                        FileName = aria2Path,
                        Arguments = string.Join(" ", args),
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        WorkingDirectory = System.IO.Path.GetDirectoryName(aria2Path) ?? "."
                    };

                    Console.WriteLine($"[Aria2Manager] Working directory: {startInfo.WorkingDirectory}");
                    Console.WriteLine($"[Aria2Manager] Full command: {aria2Path} {string.Join(" ", args)}");

                    _aria2Process = Process.Start(startInfo);
                    if (_aria2Process != null)
                    {
                        Console.WriteLine($"[Aria2Manager] Process started, PID={_aria2Process.Id}, HasExited={_aria2Process.HasExited}");

                        if (_aria2Process.HasExited)
                        {
                            Console.WriteLine($"[Aria2Manager] Process exited immediately with code: {_aria2Process.ExitCode}");
                        }

                        // 注意：由于禁用了输出重定向，不再需要 BeginOutputReadLine/BeginErrorReadLine
                        // 日志会直接输出到控制台（CreateNoWindow=true 时会丢失，但不影响功能）

                        // 等待 RPC 服务器就绪（增加超时）
                        System.Threading.Thread.Sleep(2000); // 等待进程初始化  
                        if (_waitForRpcReady(rpcPort, 30000))
                        {
                            // 进一步验证 Token 是否正确
                            if (_verifyRpcToken().GetAwaiter().GetResult())
                            {
                                _isRunning = true;
                                Console.WriteLine("[Aria2Manager] Aria2 started and RPC ready on port " + rpcPort);
                                _ = PollStatusAsync();
                                return true;
                            }
                            else
                            {
                                Console.WriteLine("[Aria2Manager] RPC port ready but Token verification failed. Possible secret mismatch with existing process.");
                            }
                        }

                        // 第一次超时，再等 10 秒
                        Console.WriteLine("[Aria2Manager] First RPC wait timeout (30s), waiting 10 more seconds...");
                        System.Threading.Thread.Sleep(10000);

                        if (_waitForRpcReady(rpcPort, 15000))
                        {
                            _isRunning = true;
                            Console.WriteLine("[Aria2Manager] Aria2 RPC ready after additional wait");
                            _ = PollStatusAsync();
                            return true;
                        }

                        // 最后一次尝试，再等 15 秒
                        Console.WriteLine("[Aria2Manager] Second timeout, waiting 15 more seconds...");
                        System.Threading.Thread.Sleep(15000);

                        if (_waitForRpcReady(rpcPort, 10000))
                        {
                            _isRunning = true;
                            Console.WriteLine("[Aria2Manager] Aria2 RPC ready after final wait");
                            _ = PollStatusAsync();
                            return true;
                        }

                        Console.WriteLine("[Aria2Manager] Warning: RPC not ready after 55 seconds total wait, checking aria2.log for errors...");
                        // 尝试读取日志文件
                        try
                        {
                            var logPath = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(aria2Path) ?? ".", "aria2.log");
                            if (System.IO.File.Exists(logPath))
                            {
                                var logContent = System.IO.File.ReadAllText(logPath);
                                Console.WriteLine($"[Aria2Manager] aria2.log content (last 2000 chars): {logContent.Substring(Math.Max(0, logContent.Length - 2000))}");
                            }
                        }
                        catch { }

                        // 继续尝试使用，RPC 可能在后续调用中就绪
                        Console.WriteLine("[Aria2Manager] Continuing anyway - RPC may become available later");
                        _isRunning = true;
                        _ = PollStatusAsync();
                        return true;
                    }
                    else
                    {
                        Console.WriteLine("[Aria2Manager] Process.Start returned null");
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Aria2Manager] Failed to start: {ex.GetType().Name}: {ex.Message}");
                    Console.WriteLine($"[Aria2Manager] Stack trace: {ex.StackTrace}");
                }

                return false;
            }
        }

        /// <summary>
        /// 等待 RPC 服务器就绪
        /// </summary>
        private bool _waitForRpcReady(int port, int timeoutMs)
        {
            var deadline = DateTime.Now.AddMilliseconds(timeoutMs);
            while (DateTime.Now < deadline)
            {
                try
                {
                    // 尝试连接 RPC 端口（使用 127.0.0.1 避免 DNS 解析问题）    
                    using var client = new System.Net.Sockets.TcpClient();      
                    client.SendTimeout = 500;
                    client.ReceiveTimeout = 500;
                    try
                    {
                        client.Connect("127.0.0.1", port);
                        Console.WriteLine($"[Aria2Manager] RPC port {port} connected successfully!");
                        return true;
                    }
                    catch (System.Net.Sockets.SocketException ex)
                    {
                        // 连接失败是正常的，继续等待
                        if (ex.SocketErrorCode == System.Net.Sockets.SocketError.ConnectionRefused)
                        {
                            // 端口还没打开，继续等待
                        }
                        else
                        {
                            Console.WriteLine($"[Aria2Manager] Socket error: {ex.SocketErrorCode}");
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Aria2Manager] Port check error: {ex.Message}");
                }
                System.Threading.Thread.Sleep(100);
            }
            return false;
        }

        /// <summary>
        /// 验证 RPC Token 是否正确
        /// </summary>
        private async Task<bool> _verifyRpcToken()
        {
            try
            {
                var request = new
                {
                    jsonrpc = "2.0",
                    id = Guid.NewGuid().ToString(),
                    method = "aria2.getVersion",
                    @params = new object[] { $"token:{_rpcToken}" }
                };

                var response = await SendRpcRequestAsync(request);
                return response != null;
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// 停止 Aria2 进程
        /// </summary>
        public void Stop()
        {
            lock (_lock)
            {
                if (_aria2Process != null && !_aria2Process.HasExited)
                {
                    try
                    {
                        // 优雅关闭
                        _aria2Process.CloseMainWindow();
                        if (!_aria2Process.WaitForExit(5000))
                        {
                            _aria2Process.Kill();
                        }
                    }
                    catch { }
                    finally
                    {
                        _aria2Process = null;
                    }
                }
                _isRunning = false;
                Console.WriteLine("[Aria2Manager] Aria2 stopped");
            }
        }

        /// <summary>
        /// 添加下载任务
        /// </summary>
        public async Task<string> AddDownloadAsync(string url, string savePath, Dictionary<string, string>? options = null)
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.addUri",
                @params = new object[]
                {
                    $"token:{_rpcToken}",
                    new[] { url },
                    options ?? new Dictionary<string, string>()
                }
            };

            var response = await SendRpcRequestAsync(request);
            if (response != null && response.Value.TryGetProperty("result", out var result))
            {
                var gid = result.ToString();
                _activeDownloads[gid] = new Aria2Download
                {
                    Gid = gid,
                    Url = url,
                    SavePath = savePath,
                    Status = "active"
                };
                Console.WriteLine("[Aria2Manager] Added download: " + gid);     
                return gid;
            }

            throw new Exception("Failed to add download: " + response?.ToString());
        }

        /// <summary>
        /// 暂停下载
        /// </summary>
        public async Task<string> PauseAsync(string gid)
        {
            try
            {
                Console.WriteLine($"[Aria2Manager] PauseAsync called for gid={gid}");
                var request = new
                {
                    jsonrpc = "2.0",
                    id = Guid.NewGuid().ToString(),
                    method = "aria2.pause",
                    @params = new object[] { $"token:{_rpcToken}", gid }        
                };

                var response = await SendRpcRequestAsync(request);
                bool success = response != null;
                Console.WriteLine($"[Aria2Manager] PauseAsync result for {gid}: {success}");
                return success ? "true" : "false";
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Aria2Manager] PauseAsync Exception: {ex.Message}");
                return "false";
            }
        }

        /// <summary>
        /// 恢复下载
        /// </summary>
        public async Task<string> UnpauseAsync(string gid)
        {
            try
            {
                Console.WriteLine($"[Aria2Manager] UnpauseAsync called for gid={gid}");
                var request = new
                {
                    jsonrpc = "2.0",
                    id = Guid.NewGuid().ToString(),
                    method = "aria2.unpause",
                    @params = new object[] { $"token:{_rpcToken}", gid }       
                };

                var response = await SendRpcRequestAsync(request);
                bool success = response != null;
                Console.WriteLine($"[Aria2Manager] UnpauseAsync result for {gid}: {success}");
                return success ? "true" : "false";
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Aria2Manager] UnpauseAsync Exception: {ex.Message}");
                return "false";
            }
        }

        /// <summary>
        /// 取消下载
        /// </summary>
        public async Task<bool> RemoveAsync(string gid)
        {
            try
            {
                Console.WriteLine($"[Aria2Manager] RemoveAsync called for gid={gid}");
                var request = new
                {
                    jsonrpc = "2.0",
                    id = Guid.NewGuid().ToString(),
                    method = "aria2.remove",
                    @params = new object[] { $"token:{_rpcToken}", gid }        
                };

                var response = await SendRpcRequestAsync(request);
                bool success = response != null;
                Console.WriteLine($"[Aria2Manager] RemoveAsync result for {gid}: {success}");
                if (success)
                {
                    _activeDownloads.Remove(gid);
                }
                return success;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Aria2Manager] RemoveAsync Exception: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// 获取下载状态（增强版：同时检查活跃和已停止列表）
        /// </summary>
        public async Task<Aria2Download?> GetStatusAsync(string gid)
        {
            Console.WriteLine($"[Aria2Manager] GetStatusAsync called for gid={gid}, IsRunning={_isRunning}");

            // 首先尝试 tellStatus 直接查询
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.tellStatus",
                @params = new object[]
                {
                    $"token:{_rpcToken}",
                    gid,
                    new[] { "status", "totalLength", "completedLength", "downloadSpeed", "files", "errorCode", "errorMessage" }
                }
            };

            var response = await SendRpcRequestAsync(request);
            if (response != null && response.Value.TryGetProperty("result", out var result))
            {
                Console.WriteLine($"[Aria2Manager] tellStatus result type: {result.ValueKind}");

                // Aria2 tellStatus 返回单个对象或数组
                JsonElement statusResult;
                if (result.ValueKind == JsonValueKind.Array)
                {
                    // 如果是数组，取第一个元素
                    Console.WriteLine($"[Aria2Manager] result is array, count: {result.GetArrayLength()}");
                    var enumerator = result.EnumerateArray();
                    if (enumerator.MoveNext())
                    {
                        statusResult = enumerator.Current;
                        Console.WriteLine($"[Aria2Manager] Using first array element");
                    }
                    else
                    {
                        Console.WriteLine($"[Aria2Manager] Array is empty!");   
                        statusResult = default;
                    }
                }
                else if (result.ValueKind == JsonValueKind.Object)
                {
                    // 直接使用对象（Aria2 tellStatus 通常返回单个对象）        
                    Console.WriteLine($"[Aria2Manager] result is object, parsing directly");
                    statusResult = result;
                }
                else
                {
                    Console.WriteLine($"[Aria2Manager] result is neither array nor object: {result.ValueKind}");
                    statusResult = default;
                }

                if (statusResult.ValueKind == JsonValueKind.Object)
                {
                    Console.WriteLine($"[Aria2Manager] tellStatus returned result for {gid}");
                    var dl = ParseDownloadStatus(statusResult);
                    if (dl != null)
                    {
                        // 确保 GID 正确（Aria2 tellStatus 返回的对象可能没有 gid 字段）
                        dl.Gid = gid;
                        return dl;
                    }
                }
            }

            // 检查 RPC 响应是否有错误
            if (response != null && response.Value.TryGetProperty("error", out var error))
            {
                Console.WriteLine($"[Aria2Manager] tellStatus RPC error: {error.GetRawText()}");
            }
            else if (response == null)
            {
                Console.WriteLine($"[Aria2Manager] tellStatus returned null (RPC call failed)");
            }

            // fallback: 尝试从活跃列表中查找
            Console.WriteLine($"[Aria2Manager] Trying to find in active downloads...");
            var activeDownloads = await GetAllDownloadsListAsync();
            Console.WriteLine($"[Aria2Manager] Active downloads count: {activeDownloads.Count}");
            var found = activeDownloads.FirstOrDefault(d => d.Gid == gid);      
            if (found != null)
            {
                Console.WriteLine($"[Aria2Manager] Found in active list: {gid}");
                return found;
            }

            // fallback: 检查已停止/完成列表（最近 100 个）
            Console.WriteLine($"[Aria2Manager] Trying to find in stopped downloads...");
            var stoppedResult = await GetStoppedDownloadsAsync();
            if (stoppedResult != null)
            {
                Console.WriteLine($"[Aria2Manager] Stopped downloads count: {stoppedResult.Count}");
                found = stoppedResult.FirstOrDefault(d => d.Gid == gid);        
                if (found != null)
                {
                    Console.WriteLine($"[Aria2Manager] Found in stopped: GID={gid}, status={found.Status}, errorCode={found.ErrorCode}, errorMessage={found.ErrorMessage}");
                    return found;
                }
            }

            Console.WriteLine($"[Aria2Manager] GetStatusAsync: GID={gid} not found anywhere");
            return null;
        }

        /// <summary>
        /// 获取已停止的下载（包括完成、错误、已移除）
        /// </summary>
        public async Task<List<Aria2Download>> GetStoppedDownloadsAsync()       
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.tellStopped",
                @params = new object[]
                {
                    $"token:{_rpcToken}",
                    0,
                    100,
                    new[] { "status", "totalLength", "completedLength", "downloadSpeed", "files", "errorCode", "errorMessage" }
                }
            };

            var response = await SendRpcRequestAsync(request);
            var downloads = new List<Aria2Download>();

            if (response != null && response.Value.TryGetProperty("result", out var result) && result.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in result.EnumerateArray())
                {
                    var dl = ParseDownloadStatus(item);
                    if (dl != null) downloads.Add(dl);
                }
            }

            return downloads;
        }

        /// <summary>
        /// 获取所有活跃下载
        /// </summary>
        public async Task<List<Aria2Download>> GetAllDownloadsListAsync()       
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.tellActive",
                @params = new object[]
                {
                    $"token:{_rpcToken}"
                }
            };

            var response = await SendRpcRequestAsync(request);
            var downloads = new List<Aria2Download>();

            if (response != null && response.Value.TryGetProperty("result", out var result) && result.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in result.EnumerateArray())
                {
                    var dl = ParseDownloadStatus(item);
                    if (dl != null) downloads.Add(dl);
                }
            }

            return downloads;
        }

        public async Task<string> GetAllDownloadsJsonAsync()
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.tellActive",
                @params = new object[]
                {
                    $"token:{_rpcToken}"
                }
            };

            var response = await SendRpcRequestAsync(request);
            if (response == null) {
                Console.WriteLine("[Aria2Manager] GetAllDownloadsJsonAsync: RPC response is null");
                return "[]";
            }

            var downloads = new List<object>();

            if (response.Value.TryGetProperty("result", out var result) && response.Value.TryGetProperty("result", out var arrayResult) && result.ValueKind == JsonValueKind.Array)
            {
                Console.WriteLine($"[Aria2Manager] tellActive returned {result.GetArrayLength()} items");
                foreach (var item in result.EnumerateArray())
                {
                    var dl = ParseDownloadStatus(item);
                    if (dl != null)
                    {
                        string? gid = dl.Gid;
                        if (string.IsNullOrEmpty(gid))
                        {
                            foreach (var kvp in _activeDownloads)
                            {
                                // URL matching - most reliable since we store original URL
                                if (!string.IsNullOrEmpty(dl.Url) && kvp.Value.Url == dl.Url)
                                {
                                    gid = kvp.Key;
                                    Console.WriteLine($"[Aria2Manager] GID matched by URL: {gid}");
                                    break;
                                }
                            }
                        }
                        if (string.IsNullOrEmpty(gid))
                        {
                            foreach (var kvp in _activeDownloads)
                            {
                                // SavePath matching as fallback
                                if (!string.IsNullOrEmpty(dl.SavePath) && kvp.Value.SavePath == dl.SavePath)
                                {
                                    gid = kvp.Key;
                                    Console.WriteLine($"[Aria2Manager] GID matched by SavePath: {gid}");
                                    break;
                                }
                            }
                        }
                        Console.WriteLine($"[Aria2Manager] Final GID for download: {gid ?? "null"}, URL: {dl.Url}, SavePath: {dl.SavePath}");
                        downloads.Add(new {
                            gid = gid ?? "",
                            status = dl.Status,
                            totalLength = dl.TotalLength,
                            completedLength = dl.CompletedLength,
                            speed = dl.Speed,
                            progress = dl.Progress,
                            url = dl.Url,
                            savePath = dl.SavePath,
                            errorCode = dl.ErrorCode,
                            errorMessage = dl.ErrorMessage
                        });
                    }
                }
            }

            return JsonSerializer.Serialize(downloads);
        }

        // Alias for WebView2 - returns JSON string
        public async Task<string> GetAllDownloadsAsync()
        {
            return await GetAllDownloadsJsonAsync();
        }

        /// <summary>
        /// 设置全局选项（连接数、速度限制等）
        /// </summary>
        public async Task SetGlobalOptionsAsync(Dictionary<string, string> options)
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.setGlobalOptions",
                @params = new object[]
                {
                    $"token:{_rpcToken}",
                    options
                }
            };

            await SendRpcRequestAsync(request);
            Console.WriteLine("[Aria2Manager] Global options updated");
        }

        /// <summary>
        /// 获取全局选项
        /// </summary>
        public async Task<Dictionary<string, string>> GetGlobalOptionsAsync()   
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.getGlobalOptions",
                @params = new object[] { $"token:{_rpcToken}" }
            };

            var response = await SendRpcRequestAsync(request);
            var options = new Dictionary<string, string>();

            if (response != null && response.Value.TryGetProperty("result", out var result) && result.ValueKind == JsonValueKind.Object)
            {
                foreach (var prop in result.EnumerateObject())
                {
                    options[prop.Name] = prop.Value.ToString();
                }
            }

            return options;
        }

        /// <summary>
        /// 轮询下载状态（后台任务）
        /// </summary>
        private async Task PollStatusAsync()
        {
            while (_isRunning)
            {
                try
                {
                    var downloads = await GetAllDownloadsListAsync();

                    foreach (var dl in downloads)
                    {
                        if (_activeDownloads.TryGetValue(dl.Gid, out var cached))
                        {
                            var progress = dl.TotalLength > 0
                                ? (int)(dl.CompletedLength * 100 / dl.TotalLength)
                                : 0;

                            if (cached.Progress != progress || cached.Speed != dl.Speed)
                            {
                                cached.Progress = progress;
                                cached.Speed = dl.Speed;
                                cached.TotalLength = dl.TotalLength;
                                cached.CompletedLength = dl.CompletedLength;    

                                ProgressChanged?.Invoke(this, (dl.Gid, progress, dl.Speed));
                            }

                            // 检查完成状态
                            if (dl.Status == "complete")
                            {
                                cached.Status = "complete";
                                DownloadComplete?.Invoke(this, cached);
                            }
                            else if (dl.Status == "error")
                            {
                                cached.Status = "error";
                                DownloadError?.Invoke(this, cached);
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[Aria2Manager] Poll error: " + ex.Message);
                }

                await Task.Delay(500); // 每 500ms 轮询一次
            }
        }

        private async Task<JsonElement?> SendRpcRequestAsync(object request)    
        {
            try
            {
                var json = JsonSerializer.Serialize(request);
                Console.WriteLine($"[Aria2Manager] RPC Request: {json.Substring(0, Math.Min(500, json.Length))}...");

                var content = new StringContent(json, Encoding.UTF8, "application/json");
                var response = await _httpClient.PostAsync(_rpcUrl, content);   

                var statusCode = (int)response.StatusCode;
                var responseBody = await response.Content.ReadAsStringAsync();  
                Console.WriteLine($"[Aria2Manager] RPC Response ({statusCode}): {responseBody.Substring(0, Math.Min(1000, responseBody.Length))}...");

                if (response.IsSuccessStatusCode)
                {
                    var doc = JsonDocument.Parse(responseBody);
                    var root = doc.RootElement;
                    
                    // 检查 Aria2 级别的错误
                    if (root.TryGetProperty("error", out var error))
                    {
                        Console.WriteLine($"[Aria2Manager] Aria2 RPC Error: {error.GetRawText()}");
                        return null; // 返回 null 表示逻辑上的失败
                    }
                    
                    return root;
                }
                else
                {
                    Console.WriteLine($"[Aria2Manager] HTTP failed with status {statusCode}: {responseBody}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Aria2Manager] RPC Exception: {ex.GetType().Name}: {ex.Message}");
                if (ex.InnerException != null)
                {
                    Console.WriteLine($"[Aria2Manager] Inner Exception: {ex.InnerException.Message}");
                }
            }
            return null;
        }

        private Aria2Download? ParseDownloadStatus(JsonElement result)
        {
            try
            {
                var dl = new Aria2Download
                {
                    // Gid 可能不在 result 中（tellStatus 返回的对象没有 gid），由调用者设置
                    Gid = result.TryGetProperty("gid", out var g) ? g.GetString() ?? "" : "",
                    Status = result.TryGetProperty("status", out var s) ? s.GetString() ?? "unknown" : "unknown",
                    TotalLength = GetJsonValueAsLong(result, "totalLength"),    
                    CompletedLength = GetJsonValueAsLong(result, "completedLength"),
                    Speed = GetJsonValueAsLong(result, "downloadSpeed"),        
                    ErrorCode = result.TryGetProperty("errorCode", out var ec) ? ec.GetString() : null,
                    ErrorMessage = result.TryGetProperty("errorMessage", out var em) ? em.GetString() : null
                };

                if (result.TryGetProperty("files", out var files) && files.ValueKind == JsonValueKind.Array && files.GetArrayLength() > 0)
                {
                    var firstFile = files[0];
                    if (firstFile.TryGetProperty("path", out var path))
                    {
                        dl.SavePath = path.GetString() ?? "";
                    }
                    // aria2 返回的 URIs 在 files[0].uris 数组中
                    if (firstFile.TryGetProperty("uris", out var uris) && uris.ValueKind == JsonValueKind.Array && uris.GetArrayLength() > 0)
                    {
                        var firstUri = uris[0];
                        if (firstUri.TryGetProperty("uri", out var uri))        
                        {
                            dl.Url = uri.GetString() ?? "";
                        }
                    }
                }

                return dl;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Aria2Manager] ParseDownloadStatus error: {ex.Message}");
                return null;
            }
        }

        // 安全地获取 JSON 数值（处理字符串或数字类型）
        private static long GetJsonValueAsLong(JsonElement parent, string propertyName)
        {
            try
            {
                if (!parent.TryGetProperty(propertyName, out var element))      
                    return 0;

                // 如果是数字类型，直接返回
                if (element.ValueKind == JsonValueKind.Number)
                    return element.GetInt64();

                // 如果是字符串类型，解析字符串
                if (element.ValueKind == JsonValueKind.String)
                {
                    var str = element.GetString();
                    if (!string.IsNullOrEmpty(str))
                    {
                        if (long.TryParse(str, out var result))
                            return result;
                        if (double.TryParse(str, out var dbl))
                            return (long)dbl;
                    }
                }

                return 0;
            }
            catch
            {
                return 0;
            }
        }

        /// <summary>
        /// 自动下载 aria2c.exe（如果不存在）
        /// </summary>
        private bool DownloadAria2Executable(string targetPath)
        {
            try
            {
                var targetDir = System.IO.Path.GetDirectoryName(targetPath);    
                if (!string.IsNullOrEmpty(targetDir) && !System.IO.Directory.Exists(targetDir))
                {
                    System.IO.Directory.CreateDirectory(targetDir);
                }

                // GitHub release 页面直接下载链接（win-64bit 版本）
                var downloadUrl = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip";

                Console.WriteLine($"[Aria2Manager] Downloading from: {downloadUrl}");

                using var client = new HttpClient();
                client.DefaultRequestHeaders.Add("User-Agent", "STS2-ModManager/1.0");
                client.Timeout = TimeSpan.FromMinutes(5);

                var zipData = client.GetByteArrayAsync(downloadUrl).GetAwaiter().GetResult();
                Console.WriteLine($"[Aria2Manager] Downloaded {zipData.Length} bytes");

                // 保存 ZIP 临时文件
                var tempZipPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "aria2_temp.zip");
                System.IO.File.WriteAllBytes(tempZipPath, zipData);

                // 解压 ZIP
                using var archive = System.IO.Compression.ZipFile.OpenRead(tempZipPath);
                foreach (var entry in archive.Entries)
                {
                    if (entry.Name.Equals("aria2c.exe", StringComparison.OrdinalIgnoreCase))
                    {
                        var extractPath = targetPath;
                        entry.ExtractToFile(extractPath, true);
                        Console.WriteLine($"[Aria2Manager] Extracted aria2c.exe to: {extractPath}");
                        System.IO.File.Delete(tempZipPath);
                        return true;
                    }
                }

                // 如果在 ZIP 中没找到 aria2c.exe，尝试其他解压方式
                System.IO.File.Delete(tempZipPath);

                // 备选方案：直接下载独立 exe
                var altUrl = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2c.exe";
                Console.WriteLine($"[Aria2Manager] Trying alternative direct download: {altUrl}");

                try
                {
                    var exeData = client.GetByteArrayAsync(altUrl).GetAwaiter().GetResult();
                    System.IO.File.WriteAllBytes(targetPath, exeData);
                    Console.WriteLine($"[Aria2Manager] Downloaded aria2c.exe directly");
                    return true;
                }
                catch
                {
                    Console.WriteLine($"[Aria2Manager] Direct download failed");
                }

                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Aria2Manager] DownloadAria2Executable error: {ex.Message}");
                return false;
            }
        }
    }

    /// <summary>
    /// Aria2 下载任务信息
    /// </summary>
    public class Aria2Download
    {
        public string Gid { get; set; } = "";
        public string Url { get; set; } = "";
        public string SavePath { get; set; } = "";
        public string Status { get; set; } = "unknown";
        public long TotalLength { get; set; }
        public long CompletedLength { get; set; }
        public long Speed { get; set; }
        public int Progress { get; set; }
        public string? ErrorCode { get; set; }
        public string? ErrorMessage { get; set; }
    }
}
