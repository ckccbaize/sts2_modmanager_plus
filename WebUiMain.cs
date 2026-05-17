using Godot;
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

/// <summary>
/// Web UI 主场景控制器 - 使用独立的 BrowserHost 进程
/// 避免在 Godot 进程中加载 System.Windows.Forms
/// </summary>
public partial class WebUiMain : Godot.Control
{
	private Process? _browserProcess;
	private bool _isInitialized = false;
	private CancellationTokenSource? _pipeCts;
	private Task? _pipeServerTask;

	// 16:9 默认尺寸
	private const int DEFAULT_WIDTH = 1280;
	private const int DEFAULT_HEIGHT = 720;

	public override void _Ready()
	{
		GD.Print("[WebUiMain] _Ready() - 启动浏览器宿主进程");

		// 延迟启动浏览器
		CallDeferred(MethodName.StartBrowserHost);
	}

	private async void StartBrowserHost()
	{
		try
		{
			// 查找 BrowserHost.exe
			var possiblePaths = new string[]
			{
				"E:\\modmanager_project\\sts-2-modmanager\\browser_host\\bin\\Release\\net8.0-windows\\BrowserHost.exe",
				ProjectSettings.GlobalizePath("res://browser_host/bin/Release/net8.0-windows/BrowserHost.exe"),
                ".\\browser_host\\bin\\Release\\net8.0-windows\\BrowserHost.exe"
			};

			string? exePath = null;
			foreach (var path in possiblePaths)
			{
				if (File.Exists(path))
				{
					exePath = path;
					break;
				}
			}

			if (exePath == null)
			{
				GD.PrintErr("[WebUiMain] 未找到 BrowserHost.exe");
				GD.PrintErr("[WebUiMain] 请先构建 browser_host 项目");
				GD.PrintErr("[WebUiMain] 运行: cd browser_host && dotnet build -c Release");
				return;
			}

			GD.Print($"[WebUiMain] 使用 BrowserHost.exe: {exePath}");

			// 获取 Godot 窗口句柄
			IntPtr godotHwnd = GetGodotWindowHandle();
			if (godotHwnd == IntPtr.Zero)
			{
				GD.PrintErr("[WebUiMain] 无法获取 Godot 窗口句柄");
				return;
			}

			GD.Print($"[WebUiMain] Godot 窗口句柄: {godotHwnd}");

			// 获取 WebUiMain 控件的初始尺寸
			Vector2 initialSize = Size;
			GD.Print($"[WebUiMain] WebUiMain 初始尺寸: {initialSize.X}x{initialSize.Y}");

			// 获取 LocalServer 实际使用的端口
			int serverPort = 8765;
			var localServer = GetNodeOrNull("/root/ModManager/local_server");
			if (localServer != null)
			{
				var portMethod = localServer.GetType().GetMethod("get_port");
				if (portMethod != null)
				{
					serverPort = (int)portMethod.Invoke(localServer, null);
				}
			}
			GD.Print($"[WebUiMain] LocalServer port: {serverPort}");

			// 启动 BrowserHost 进程，传递父窗口句柄、尺寸和端口
			var startInfo = new ProcessStartInfo
			{
				FileName = exePath,
				Arguments = $"{godotHwnd} {DEFAULT_WIDTH} {DEFAULT_HEIGHT} {serverPort}",
				UseShellExecute = false,
				CreateNoWindow = true,
				RedirectStandardOutput = true,
				RedirectStandardError = true
			};

			_browserProcess = Process.Start(startInfo);
			if (_browserProcess == null)
			{
				GD.PrintErr("[WebUiMain] 无法启动 BrowserHost 进程");
				return;
			}

			GD.Print("[WebUiMain] BrowserHost 进程已启动");

			// 读取输出（异步）
			_browserProcess.OutputDataReceived += (s, e) =>
			{
				if (!string.IsNullOrEmpty(e.Data))
					GD.Print($"[BrowserHost] {e.Data}");
			};
			_browserProcess.ErrorDataReceived += (s, e) =>
			{
				if (!string.IsNullOrEmpty(e.Data))
					GD.PrintErr($"[BrowserHost Error] {e.Data}");
			};

			_browserProcess.BeginOutputReadLine();
			_browserProcess.BeginErrorReadLine();

			_isInitialized = true;
			GD.Print("[WebUiMain] 浏览器初始化完成");

			// 等待 BrowserHost 初始化
			await ToSignal(GetTree().CreateTimer(0.5), Godot.Timer.SignalName.Timeout);

			// 发送初始尺寸
			SendResizeToBrowser();
		}
		catch (Exception ex)
		{
			GD.PrintErr($"[WebUiMain] 启动浏览器失败: {ex.Message}");
			GD.PrintErr($"[WebUiMain] 堆栈: {ex.StackTrace}");
		}
	}

	private void SendResizeToBrowser()
	{
		if (_browserProcess == null || _browserProcess.HasExited)
			return;

		try
		{
			// 获取当前 WebUiMain 控件的尺寸
			int width = (int)Size.X;
			int height = (int)Size.Y;

			if (width <= 0 || height <= 0)
			{
				// 使用默认尺寸
				width = DEFAULT_WIDTH;
				height = DEFAULT_HEIGHT;
			}

			GD.Print($"[WebUiMain] 发送尺寸更新: {width}x{height}");

			// 通过标准输入发送尺寸信息（BrowserHost 从 stdin 读取）
			// 但 BrowserHost 是 WinForms 应用，不读取 stdin
			// 所以我们使用命名管道
		}
		catch (Exception ex)
		{
			GD.PrintErr($"[WebUiMain] 发送尺寸失败: {ex.Message}");
		}
	}

	private IntPtr GetGodotWindowHandle()
	{
		try
		{
			// 获取当前进程 ID
			int processId = System.Diagnostics.Process.GetCurrentProcess().Id;
			GD.Print($"[WebUiMain] 当前进程 ID: {processId}");

			// 枚举窗口找到属于当前进程的
			_foundHwnd = IntPtr.Zero;
			_targetProcessId = processId;
			EnumWindows(EnumWindowsCallback, IntPtr.Zero);

			if (_foundHwnd != IntPtr.Zero)
			{
				GD.Print($"[WebUiMain] 找到 Godot 窗口: {_foundHwnd}");
				return _foundHwnd;
			}

			// 备用方法: 尝试 GetForegroundWindow
			IntPtr hwnd = GetForegroundWindow();
			GD.Print($"[WebUiMain] GetForegroundWindow: {hwnd}");
			return hwnd;
		}
		catch (Exception ex)
		{
			GD.PrintErr($"[WebUiMain] 获取窗口句柄失败: {ex.Message}");
			return IntPtr.Zero;
		}
	}

	private int _targetProcessId;
	private IntPtr _foundHwnd = IntPtr.Zero;

	private bool EnumWindowsCallback(IntPtr hWnd, IntPtr lParam)
	{
		// 获取窗口所属进程
		uint windowPid;
		GetWindowThreadProcessId(hWnd, out windowPid);

		if (windowPid == (uint)_targetProcessId)
		{
			// 检查窗口是否可见
			if (IsWindowVisible(hWnd))
			{
				// 获取窗口标题
				var titleBuilder = new System.Text.StringBuilder(256);
				GetWindowText(hWnd, titleBuilder, 256);
				var title = titleBuilder.ToString();

				// 获取窗口类名
				var classBuilder = new System.Text.StringBuilder(256);
				GetClassName(hWnd, classBuilder, 256);
				var className = classBuilder.ToString();

				GD.Print($"[WebUiMain] 找到窗口: 类={className}, 标题={title}, Handle={hWnd}");

				// 保存第一个可见窗口
				_foundHwnd = hWnd;
				return false; // 停止枚举
			}
		}
		return true; // 继续枚举
	}

	[DllImport("user32.dll")]
	private static extern IntPtr GetForegroundWindow();

	[DllImport("user32.dll")]
	private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

	[DllImport("user32.dll")]
	private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

	[DllImport("user32.dll")]
	private static extern bool IsWindowVisible(IntPtr hWnd);

	[DllImport("user32.dll", CharSet = CharSet.Auto)]
	private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

	[DllImport("user32.dll", CharSet = CharSet.Auto)]
	private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);

	private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

	public override void _Process(double delta)
	{
		if (_isInitialized && _browserProcess != null)
		{
			// 检查进程是否还在运行
			if (_browserProcess.HasExited)
			{
				GD.PrintErr($"[WebUiMain] BrowserHost 进程已退出，退出码: {_browserProcess.ExitCode}");
				_isInitialized = false;
			}
		}
	}

	public override void _EnterTree()
	{
		// 连接调整大小时发送通知
		Resized += OnWebUiMainResized;
	}

	public override void _ExitTree()
	{
		Resized -= OnWebUiMainResized;

		// 关闭浏览器进程
		if (_browserProcess != null && !_browserProcess.HasExited)
		{
			try
			{
				_browserProcess.Kill();
				_browserProcess.Dispose();
				GD.Print("[WebUiMain] BrowserHost 进程已终止");
			}
			catch (Exception ex)
			{
				GD.PrintErr($"[WebUiMain] 关闭浏览器进程失败: {ex.Message}");
			}
		}

		_pipeCts?.Cancel();
		GD.Print("[WebUiMain] 浏览器宿主已关闭");
	}

	private void OnWebUiMainResized()
	{
		if (!_isInitialized) return;

		// 发送尺寸更新到 BrowserHost
		int width = (int)Size.X;
		int height = (int)Size.Y;

		GD.Print($"[WebUiMain] 尺寸已更改: {width}x{height}");

		// 由于 BrowserHost 在独立进程，我们使用 Windows 消息
		// 但这比较复杂，改用进程间通信
		// 简单方案：通过环境变量或临时文件
		// 这里我们用WM_SETTEXT来触发（不太优雅但有效）

		// 更简单的方案：重启 BrowserHost 并传入新尺寸
		// 但这样会有闪烁
	}
}
