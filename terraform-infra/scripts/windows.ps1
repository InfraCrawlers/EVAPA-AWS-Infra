<powershell>
Start-Transcript -Path "C:\vuln-setup-log.txt" -Append
$ErrorActionPreference = "Continue"

# Helper: Safe Download 
function Download-File {
    param([string]$Url, [string]$OutFile, [int]$Retries = 3, [int]$MinBytes = 50000)
    $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $outDir = Split-Path $OutFile -Parent
    if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    for ($i = 1; $i -le $Retries; $i++) {
        Write-Host "[*] Downloading: $Url (Attempt $i/$Retries)"
        try {
            & curl.exe -L -A $userAgent -o $OutFile $Url
            if ((Get-Item $OutFile -ErrorAction SilentlyContinue).Length -ge $MinBytes) { return $true }
        } catch {}

        try {
            Invoke-WebRequest -Uri $Url -Headers @{"User-Agent"=$userAgent} -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
            if ((Get-Item $OutFile -ErrorAction SilentlyContinue).Length -ge $MinBytes) { return $true }
        } catch {}
        
        Start-Sleep -Seconds 5
    }
    return $false
}

# 1. Weak OS posture
Write-Host "[*] Configuring OS posture..."
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Set-Service -Name wuauserv -StartupType Disabled

$regAU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (!(Test-Path $regAU)) { New-Item -Path $regAU -Force | Out-Null }
Set-ItemProperty -Path $regAU -Name NoAutoUpdate -Value 1 -Type DWord

$schannel = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
foreach ($proto in @("TLS 1.0\Client", "TLS 1.0\Server", "TLS 1.1\Client", "TLS 1.1\Server")) {
    $path = Join-Path $schannel $proto
    if (!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name "Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name "DisabledByDefault" -Value 0 -PropertyType DWord -Force | Out-Null
}

# 2. Directories & Firewall
$WORKDIR = "C:\vulnapps"
$DOWNLOADS = "$WORKDIR\downloads"
"elasticsearch" | ForEach-Object { New-Item -Path "$WORKDIR\$_" -ItemType Directory -Force | Out-Null }
New-Item -Path $DOWNLOADS -ItemType Directory -Force | Out-Null

Add-MpPreference -ExclusionPath $WORKDIR -ErrorAction SilentlyContinue
# Removed Port 8080 from the firewall list
New-NetFirewallRule -DisplayName "VulnLab-Inbound" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 21,80,443,9200,9300 -ErrorAction SilentlyContinue

# 3. Install Java 8 & Force Global Registry Update (Needed for ES 1.1)
$javaInstaller = "$DOWNLOADS\java8_installer.msi"
$javaUrl = "https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u352-b08/OpenJDK8U-jdk_x64_windows_hotspot_8u352b08.msi"
if (Download-File $javaUrl $javaInstaller) {
    Start-Process msiexec.exe -ArgumentList "/i `"$javaInstaller`" /qn ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome" -Wait
    Start-Sleep -Seconds 15 
    
    $javaPath = (Get-ChildItem -Path "C:\Program Files" -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "jdk*" -or $_.Name -like "jre*" } | Select-Object -First 1).FullName
    if ($javaPath) { 
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $javaPath, "Machine")
        $env:JAVA_HOME = $javaPath
        Write-Host "[+] Global JAVA_HOME set to: $javaPath"
    }
}

# 4. Download Vulnerable Software
$files = @(
    @{ Url="https://zenlayer.dl.sourceforge.net/project/filezilla/FileZilla%20Server/0.9.41/FileZilla_Server-0_9_41.exe"; Out="$DOWNLOADS\filezilla_setup.exe" },
    @{ Url="https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.1.1.zip"; Out="$DOWNLOADS\elasticsearch.zip" }
)
foreach ($f in $files) { Download-File $f.Url $f.Out | Out-Null }

# 5. Granular .NET Extraction
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Extract-ZipSafe($ZipPath, $DestPath) {
    if (!(Test-Path $DestPath)) { New-Item -ItemType Directory -Path $DestPath -Force | Out-Null }
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.EndsWith("/") -or $entry.FullName.EndsWith("\")) { continue }
            $safeName = $entry.FullName -replace '[:\?\*<>\|"\[\]]', '_'
            $targetFile = [System.IO.Path]::Combine($DestPath, $safeName)
            $targetDir = [System.IO.Path]::GetDirectoryName($targetFile)
            if (!(Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
            try { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetFile, $true) } catch {}
        }
        $archive.Dispose()
    } catch { Write-Host "[!] Extraction failed: $_" }
}

Extract-ZipSafe "$DOWNLOADS\elasticsearch.zip" "$WORKDIR\elasticsearch"
Get-ChildItem "$WORKDIR\elasticsearch\elasticsearch-*" -Directory -ErrorAction SilentlyContinue | Get-ChildItem | Move-Item -Destination "$WORKDIR\elasticsearch" -Force

# 6. Apply Application Patches (Fixing Elasticsearch Memory Crash)
Write-Host "[*] Patching ancient applications..."
if (Test-Path "$WORKDIR\elasticsearch\lib\sigar") {
    Remove-Item -Path "$WORKDIR\elasticsearch\lib\sigar" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Removed incompatible Sigar library from Elasticsearch."
}

# 7. Setup FileZilla
if (Test-Path "$DOWNLOADS\filezilla_setup.exe") {
    if ((Get-Item "$DOWNLOADS\filezilla_setup.exe").Length -gt 1MB) {
        Start-Process "$DOWNLOADS\filezilla_setup.exe" -ArgumentList "/S" -Wait
        Start-Sleep -Seconds 10
        
        $fzExe = "C:\Program Files (x86)\FileZilla Server\FileZilla server.exe"
        if (Test-Path $fzExe) {
            Write-Host "[*] Forcing FileZilla service installation..."
            Start-Process -FilePath $fzExe -ArgumentList "/install auto" -Wait
            Start-Process -FilePath $fzExe -ArgumentList "/start" -Wait
        }
    }
}

# 8. Configure Elasticsearch
$esConfig = "$WORKDIR\elasticsearch\config\elasticsearch.yml"
if (Test-Path $esConfig) {
    @"
network.host: 0.0.0.0
http.port: 9200
discovery.zen.ping.multicast.enabled: false
"@ | Out-File $esConfig -Append -Encoding UTF8
}

if (Test-Path "$WORKDIR\elasticsearch\bin\elasticsearch.bat") {
    Start-Process "$WORKDIR\elasticsearch\bin\elasticsearch.bat" -WorkingDirectory "$WORKDIR\elasticsearch\bin" -WindowStyle Hidden
}

# 9. Startup Persistence
$startupScript = "C:\vulnapps\start-services.ps1"
@"
`$env:JAVA_HOME = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
if (-not `$env:JAVA_HOME) { `$env:JAVA_HOME = (Get-ChildItem -Path 'C:\Program Files' -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like 'jdk*' -or `$_.Name -like 'jre*' } | Select-Object -First 1).FullName }

if (Test-Path 'C:\vulnapps\elasticsearch\bin\elasticsearch.bat') { 
    Start-Process 'C:\vulnapps\elasticsearch\bin\elasticsearch.bat' -WorkingDirectory 'C:\vulnapps\elasticsearch\bin' -WindowStyle Hidden
}

if (Test-Path 'C:\Program Files (x86)\FileZilla Server\FileZilla server.exe') {
    Start-Process 'C:\Program Files (x86)\FileZilla Server\FileZilla server.exe' -ArgumentList '/start' -WindowStyle Hidden
}
"@ | Out-File $startupScript -Encoding UTF8

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startupScript`""
Register-ScheduledTask -TaskName "VulnLabStartup" -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest) -Force | Out-Null

"Lab Build Success: $(Get-Date)" | Out-File C:\vuln-build-complete.txt
Stop-Transcript
</powershell>