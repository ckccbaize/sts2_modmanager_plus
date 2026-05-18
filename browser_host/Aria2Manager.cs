using System;
using System.Collections.Generic;
using System.Diagnostics;
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
                    // 构建启动参数
                    var args = new List<string>
                    {
                        "--enable-rpc",
                        $"--rpc-listen-port={rpcPort}",
                        "--rpc-listen-all",
                        "--continue=true",
                        "--split=16",
                        "--max-connection-per-server=16",
                        "--min-split-size=10M",
                        "--disk-cache=32M",
                        "--enable-http-pipelining=true",
                        "--http-accept-gzip=true"
                    };

                    var startInfo = new ProcessStartInfo
                    {
                        FileName = aria2Path,
                        Arguments = string.Join(" ", args),
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    };

                    _aria2Process = Process.Start(startInfo);
                    if (_aria2Process != null)
                    {
                        _aria2Process.OutputDataReceived += (s, e) => Console.WriteLine($"[Aria2] {e.Data}");
                        _aria2Process.ErrorDataReceived += (s, e) => Console.WriteLine($"[Aria2 Error] {e.Data}");
                        _aria2Process.BeginOutputReadLine();
                        _aria2Process.BeginErrorReadLine();

                        _isRunning = true;
                        Console.WriteLine("[Aria2Manager] Aria2 started on port " + rpcPort);

                        // 启动状态轮询
                        _ = PollStatusAsync();

                        return true;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[Aria2Manager] Failed to start: " + ex.Message);
                }

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
            if (response != null && response.TryGetProperty("result", out var result))
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
        /// 获取下载状态
        /// </summary>
        public async Task<Aria2Download?> GetStatusAsync(string gid)
        {
            var request = new
            {
                jsonrpc = "2.0",
                id = Guid.NewGuid().ToString(),
                method = "aria2.tellStatus",
                @params = new object[]
                {
                    $"token:{_rpcToken}",
                    gid,
                    new[] { "status", "totalLength", "completedLength", "downloadSpeed", "files" }
                }
            };

            var response = await SendRpcRequestAsync(request);
            if (response != null && response.TryGetProperty("result", out var result))
            {
                return ParseDownloadStatus(result);
            }
            return null;
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

            if (response != null && response.TryGetProperty("result", out var result) && result.ValueKind == JsonValueKind.Array)
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
                var content = new StringContent(json, Encoding.UTF8, "application/json");
                var response = await _httpClient.PostAsync(_rpcUrl, content);

                if (response.IsSuccessStatusCode)
                {
                    var responseBody = await response.Content.ReadAsStringAsync();
                    var doc = JsonDocument.Parse(responseBody);
                    return doc.RootElement;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("[Aria2Manager] RPC error: " + ex.Message);
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
                    Speed = result.TryGetProperty("downloadSpeed", out var sp) ? long.Parse(sp.GetString() ?? "0") : 0
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
    }
}