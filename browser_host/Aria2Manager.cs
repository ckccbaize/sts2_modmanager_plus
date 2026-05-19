using System;
using System.Collections.Generic;
using System.Diagnostics;
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

                    // 检查进程是否已经在运行
                    var existingProcesses = System.Diagnostics.Process.GetProcessesByName("aria2c");
                    Console.WriteLine($"[Aria2Manager] Existing aria2c processes: {existingProcesses.Length}");
                    foreach (var p in existingProcesses)
                    {
                        Console.WriteLine($"[Aria2Manager] Found: PID={p.Id}, Path={GetProcessPath(p.Id)}");
                    }

                    // 构建启动参数
                    var args = new List<string>
                    {
                        "--enable-rpc",
                        $"--rpc-listen-port={rpcPort}",
                        "--rpc-listen-all",
                        "--rpc-secret=sts2-mod-manager",
                        "--continue=true",
                        "--split=16",
                        "--max-connection-per-server=16",
                        "--min-split-size=10M",
                        "--disk-cache=32M",
                        "--enable-http-pipelining=true",
                        "--http-accept-gzip=true",
                        // 禁用 SSL 证书验证（Nexus CDN 等站点需要）
                        "--check-certificate=false",
                        "--check-serve-cache=true",
                        // 禁用 IPv6 避免连接问题
                        "--disable-ipv6=true",
                        // 清除代理设置
                        "--all-proxy=",
                        "--all-proxy-user=",
                        "--all-proxy-pass=",
                        // 更多连接选项
                        "--retry-wait=5",
                        "--max-file-not-found=5",
                        // 输出级别
                        "-l", "aria2.log"
                    };

                    var startInfo = new ProcessStartInfo
                    {
                        FileName = aria2Path,
                        Arguments = string.Join(" ", args),
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true,
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

                        _aria2Process.OutputDataReceived += (s, e) => Console.WriteLine($"[Aria2] {e.Data}");
                        _aria2Process.ErrorDataReceived += (s, e) => Console.WriteLine($"[Aria2 Error] {e.Data}");
                        _aria2Process.BeginOutputReadLine();
                        _aria2Process.BeginErrorReadLine();

                        // 等待 RPC 服务器就绪（最多等待 5 秒）
                        if (_waitForRpcReady(rpcPort, 5000))
                        {
                            _isRunning = true;
                            Console.WriteLine("[Aria2Manager] Aria2 started and RPC ready on port " + rpcPort);

                            // 启动状态轮询
                            _ = PollStatusAsync();

                            return true;
                        }
                        else
                        {
                            Console.WriteLine("[Aria2Manager] Aria2 started but RPC not ready");
                        }
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
                    // 尝试连接 RPC 端口
                    using var client = new System.Net.Sockets.TcpClient();
                    var result = client.BeginConnect("localhost", port, null, null);
                    var waitResult = result.AsyncWaitHandle.WaitOne(500);
                    if (waitResult && client.Connected)
                    {
                        client.EndConnect(result);
                        Console.WriteLine("[Aria2Manager] RPC port " + port + " is ready");
                        return true;
                    }
                }
                catch { }
                System.Threading.Thread.Sleep(100);
            }
            return false;
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
        public async Task<bool> PauseAsync(string gid)
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.pause",
                @params = new object[] { $"token:{_rpcToken}", gid }
            };

            var response = await SendRpcRequestAsync(request);
            return response != null;
        }

        /// <summary>
        /// 恢复下载
        /// </summary>
        public async Task<bool> UnpauseAsync(string gid)
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.unpause",
                @params = new object[] { $"token:{_rpcToken}", gid }
            };

            var response = await SendRpcRequestAsync(request);
            return response != null;
        }

        /// <summary>
        /// 取消下载
        /// </summary>
        public async Task<bool> RemoveAsync(string gid)
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.remove",
                @params = new object[] { $"token:{_rpcToken}", gid }
            };

            var response = await SendRpcRequestAsync(request);
            if (response != null)
            {
                _activeDownloads.Remove(gid);
                return true;
            }
            return false;
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
                // result 可能是对象或数组（包含一个对象）
                JsonElement statusResult;
                if (result.ValueKind == JsonValueKind.Array)
                {
                    // 如果是数组，取第一个元素
                    statusResult = result.EnumerateArray().FirstOrDefault();
                }
                else
                {
                    statusResult = result;
                }

                if (statusResult.ValueKind == JsonValueKind.Object)
                {
                    Console.WriteLine($"[Aria2Manager] tellStatus returned result for {gid}");
                    return ParseDownloadStatus(statusResult);
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
            var activeDownloads = await GetAllDownloadsAsync();
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
        public async Task<List<Aria2Download>> GetAllDownloadsAsync()
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.tellActive",
                @params = new object[]
                {
                    $"token:{_rpcToken}",
                    new[] { "status", "totalLength", "completedLength", "downloadSpeed", "files" }
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
                    var downloads = await GetAllDownloadsAsync();

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
                Console.WriteLine($"[Aria2Manager] RPC Request: {json.Substring(0, Math.Min(200, json.Length))}...");

                var content = new StringContent(json, Encoding.UTF8, "application/json");
                var response = await _httpClient.PostAsync(_rpcUrl, content);

                var statusCode = (int)response.StatusCode;
                var responseBody = await response.Content.ReadAsStringAsync();
                Console.WriteLine($"[Aria2Manager] RPC Response ({statusCode}): {responseBody.Substring(0, Math.Min(300, responseBody.Length))}...");

                if (response.IsSuccessStatusCode)
                {
                    var doc = JsonDocument.Parse(responseBody);
                    return doc.RootElement;
                }
                else
                {
                    Console.WriteLine($"[Aria2Manager] RPC failed with status {statusCode}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Aria2Manager] RPC error: {ex.GetType().Name}: {ex.Message}");
            }
            return null;
        }

        private Aria2Download? ParseDownloadStatus(JsonElement result)
        {
            try
            {
                var dl = new Aria2Download
                {
                    Gid = result.GetProperty("gid").GetString() ?? "",
                    Status = result.GetProperty("status").GetString() ?? "unknown",
                    TotalLength = result.TryGetProperty("totalLength", out var tl) ? long.Parse(tl.GetString() ?? "0") : 0,
                    CompletedLength = result.TryGetProperty("completedLength", out var cl) ? long.Parse(cl.GetString() ?? "0") : 0,
                    Speed = result.TryGetProperty("downloadSpeed", out var sp) ? long.Parse(sp.GetString() ?? "0") : 0,
                    ErrorCode = result.TryGetProperty("errorCode", out var ec) ? ec.GetString() : null,
                    ErrorMessage = result.TryGetProperty("errorMessage", out var em) ? em.GetString() : null
                };

                if (result.TryGetProperty("files", out var files) && files.ValueKind == JsonValueKind.Array)
                {
                    var firstFile = files[0];
                    if (firstFile.TryGetProperty("path", out var path))
                    {
                        dl.SavePath = path.GetString() ?? "";
                    }
                }

                return dl;
            }
            catch
            {
                return null;
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
