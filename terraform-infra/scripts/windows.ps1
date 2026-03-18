<powershell>
# --- 1. Configure Intentional Vulnerable OS State ---
Write-Host "[*] Disabling Windows Updates..." -ForegroundColor Red
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Set-Service -Name wuauserv -StartupType Disabled

$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force }
Set-ItemProperty -Path $registryPath -Name NoAutoUpdate -Value 1 -Type DWord

"Intentional vulnerable state configured: $(Get-Date)" | Out-File C:\vuln-lab.txt

# --- 2. Environment Setup & Defender Bypass ---
$WORKDIR = "C:\vulnapps"
$WWWROOT = "C:\xampp\htdocs"
if (!(Test-Path $WORKDIR)) { New-Item -Path $WORKDIR -ItemType Directory }

Write-Host "[*] Adding Defender exclusions for lab directories..." -ForegroundColor Cyan
Add-MpPreference -ExclusionPath $WORKDIR
Add-MpPreference -ExclusionPath "C:\xampp"

# Open Firewall for Lab Services (HTTP, Tomcat, Elasticsearch, FTP)
Write-Host "[*] Configuring Firewall Rules..." -ForegroundColor Cyan
New-NetFirewallRule -DisplayName "VulnLab-Inbound" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80,443,8080,9200,21,6200

Set-Location $WORKDIR

# --- 3. Install Java 8 (OpenJDK 8 via Adoptium) ---
Write-Host "[*] Installing Java 8..." -ForegroundColor Yellow
$javaUrl = "https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u352-b08/OpenJDK8U-jdk_x64_windows_hotspot_8u352b08.msi"
Invoke-WebRequest -Uri $javaUrl -OutFile "java8_installer.msi"
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i java8_installer.msi /qn ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome" -Wait
Remove-Item "java8_installer.msi"

# --- 4. Install XAMPP (PHP 7.4 Legacy) ---
Write-Host "[*] Installing XAMPP (PHP 7.4)..." -ForegroundColor Yellow
$xamppUrl = "https://sourceforge.net/projects/xampp/files/XAMPP%20Windows/7.4.27/xampp-windows-x64-7.4.27-2-VC15-installer.exe/download"
Invoke-WebRequest -Uri $xamppUrl -OutFile "xampp_installer.exe"
Start-Process -FilePath ".\xampp_installer.exe" -ArgumentList "--mode unattended --prefix C:\xampp" -Wait
Remove-Item "xampp_installer.exe"

# --- 5. Configure MySQL Root Password & Create Databases ---
Write-Host "[*] Configuring MySQL and Creating Lab Databases..." -ForegroundColor Cyan
Start-Process -FilePath "C:\xampp\mysql\bin\mysqld.exe" -ArgumentList "--skip-grant-tables"
Start-Sleep -Seconds 10 # Extra time for cloud disk I/O

# Set root password to 'password123'
$passCmd = "UPDATE mysql.user SET Password=PASSWORD('password123') WHERE User='root'; FLUSH PRIVILEGES;"
$passCmd | & "C:\xampp\mysql\bin\mysql.exe" -u root

# Create the databases
$dbCmd = "CREATE DATABASE IF NOT EXISTS wordpress; CREATE DATABASE IF NOT EXISTS drupal;"
$dbCmd | & "C:\xampp\mysql\bin\mysql.exe" -u root -ppassword123

Stop-Process -Name mysqld -Force -ErrorAction SilentlyContinue

# --- 6. Download and Extract Apps ---
Write-Host "[*] Downloading Vulnerable Software Stack..." -ForegroundColor Yellow

# FTP, Struts, Tomcat, Elasticsearch
$apps = @(
    @{ URL="https://download.filezilla-project.org/server/FileZilla_Server-0_9_41.exe"; Out="filezilla_setup.exe"; Dest="$WORKDIR" },
    @{ URL="https://archive.apache.org/dist/struts/2.3.20.1/struts-2.3.20.1-all.zip"; Out="struts.zip"; Dest="$WORKDIR\struts" },
    @{ URL="https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.15/bin/apache-tomcat-8.5.15-windows-x64.zip"; Out="tomcat.zip"; Dest="$WORKDIR\tomcat" },
    @{ URL="https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.1.1.zip"; Out="elasticsearch.zip"; Dest="$WORKDIR\elasticsearch" }
)

foreach ($app in $apps) {
    Invoke-WebRequest -Uri $app.URL -OutFile $app.Out
    if ($app.Out -like "*.zip") {
        Expand-Archive -Path $app.Out -DestinationPath $app.Dest -Force
        Remove-Item $app.Out
    }
}

# WordPress & Drupal
Invoke-WebRequest -Uri "https://wordpress.org/wordpress-4.7.1.zip" -OutFile "wp.zip"
Expand-Archive -Path "wp.zip" -DestinationPath $WWWROOT -Force

Invoke-WebRequest -Uri "https://ftp.drupal.org/files/projects/drupal-7.31.zip" -OutFile "drupal.zip"
Expand-Archive -Path "drupal.zip" -DestinationPath $WWWROOT -Force
Remove-Item *.zip -ErrorAction SilentlyContinue

# --- 7. Automate WordPress Configuration ---
Write-Host "[*] Automating WordPress wp-config.php..." -ForegroundColor Cyan
$wpPath = "$WWWROOT\wordpress"
if (Test-Path "$wpPath\wp-config-sample.php") {
    $configTemplate = Get-Content "$wpPath\wp-config-sample.php" -Raw
    $configContent = $configTemplate -replace "database_name_here", "wordpress" `
                                     -replace "username_here", "root" `
                                     -replace "password_here", "password123"
    $configContent | Out-File "$wpPath\wp-config.php" -Encoding UTF8
}

# --- 8. Finalize and Reboot ---
Write-Host "[*] Lab Setup Complete. Rebooting to apply environment changes..." -ForegroundColor Green
"Lab Build Success: $(Get-Date)" | Out-File C:\vuln-build-complete.txt

Restart-Computer -Force
</powershell>