# update-install.ps1
param(
    [string]$SourceDir,
    [string]$DestDir,
    [string]$ZipPath
)

# 等待原程序退出
Start-Sleep -Seconds 3

# 复制新文件
if (Test-Path $SourceDir) {
    $files = Get-ChildItem -Path $SourceDir -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $destFile = Join-Path $DestDir $file.Name
        Copy-Item -Path $file.FullName -Destination $destFile -Force
    }

    # 清理临时解压目录
    Remove-Item -Path $SourceDir -Recurse -Force -ErrorAction SilentlyContinue
}

# 删除 zip 包
if (Test-Path $ZipPath) {
    Remove-Item -Path $ZipPath -Force
}

# 启动新版本
$exeFiles = Get-ChildItem -Path $DestDir -Filter "*.exe" -ErrorAction SilentlyContinue
if ($exeFiles) {
    Start-Process $exeFiles[0].FullName
}

# 删除自身
Start-Sleep -Seconds 2
try {
    Remove-Item -Path $MyInvocation.InvocationName -Force -ErrorAction Stop
} catch {
    # 忽略删除失败
}