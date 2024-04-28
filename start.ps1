# Initialize variables
$LAST_SPINNER_PID = $null
$OLLAMA_BINARY = Join-Path -Path $(Get-Location) -ChildPath 'bin\ollama'
$COLLECTOR_BINARY = Join-Path -Path $(Get-Location) -ChildPath 'bin\collector'
$OLLAMA_PID = Join-Path -Path $(Get-Location) -ChildPath 'ollama.pid'
$ProgressPreference = 'SilentlyContinue'
$ollamaInstaller = 'OllamaSetup.exe'
$localURL = 'http://localhost:11434/api/version'
$remoteURL = 'https://api.github.com/repos/ollama/ollama/releases/latest'
$installerArgs = '/SILENT /VERYSILENT /SP /SUPPRESSMSGBOXES /LOG="install.log" /FORCECLOSEAPPLICATIONS /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /NORESTART'
$ollamaApp = 'ollama app'
$ollamaAppPath = (Join-Path -Path $env:LOCALAPPDATA -ChildPath '\Programs\Ollama\ollama app.exe')

# create localURL variable by joining http:// + $env:OLLAMA_HOST + :11434/api/version.  If OLLAMA_HOST is not set, use localhost.
# Validate OLLAMA_HOST.  If it is not a valid IP address, keep the default value. If it is a valid IP in the RFC1918 range, use it. If it is a domain name, use it.  If it is 127.0.0.1 or 0.0.0.0, use localhost. If it is any other IP, use it.
if ($env:OLLAMA_HOST -match '^(?:[1-9]{1,3}\.){3}[0-9]{1,3}$') {
    $ip = [System.Net.IPAddress]::Parse($env:OLLAMA_HOST)
    if ($ip.AddressFamily -eq 'InterNetwork') {
        $octets = $ip.GetAddressBytes()
        if ($octets[0] -eq 10) {
            Write-Host "Using OLLAMA_HOST environment variable: $env:OLLAMA_HOST"
            $localURL = "http://$env:OLLAMA_HOST:11434/api/version"
            # exit
        } elseif ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) {
            Write-Host "Using OLLAMA_HOST environment variable: $env:OLLAMA_HOST"
            $localURL = "http://$env:OLLAMA_HOST:11434/api/version"
            # exit
        } elseif ($octets[0] -eq 192 -and $octets[1] -eq 168) {
            Write-Host "Using OLLAMA_HOST environment variable: $env:OLLAMA_HOST"
            $localURL = "http://$env:OLLAMA_HOST:11434/api/version"
            # exit
        } else {
            Write-Host "Using OLLAMA_HOST environment variable: $env:OLLAMA_HOST"
            $localURL = "http://$env:OLLAMA_HOST:11434/api/version"
            # exit
        }
    }
}
    # Write-Host "Using OLLAMA_HOST environment variable: $env:OLLAMA_HOST"
    # $localURL = "http://$env:OLLAMA_HOST:11434/api/version"
    # exit


# Kill background processes on exit
function Exit-Trap {
    # Kill the last spinner process
    Stop-Spinner
}
# Add-TypeHandler -PreExit -ScriptBlock { Exit-Trap }
function Start-Spinner {
    param ($Seconds)

    $spinstr = '/-\|'
    $endIndex = [Math]::Floor($Seconds / 0.1)
    for ($i = 0; $i -lt $endIndex; $i++) { 
        Write-Host -NoNewLine -ForegroundColor Green "$spinstr[$i % $spinstr.Length]"
        Start-Sleep -s 0.1
    }
    if ($Seconds -ge $Seconds) { # assume a minimum of 5 seconds to display the message
        Write-Host "\b\bdone" -NoNewLine
    }
}

function Stop-Spinner {
    if ($LAST_SPINNER_PID) { 
        Get-Process -Id $LAST_SPINNER_PID | Stop-Process -Force
        Wait-Process -Id $LAST_SPINNER_PID
        Write-Host "\b\bdone" -NoNewLine
        $LAST_SPINNER_PID = $null
    }
}

function Countdown-Timer {
    param ($Seconds)

    $j = $Seconds

    $symbols = @("⣾⣿", "⣽⣿", "⣻⣿", "⢿⣿", "⡿⣿", "⣟⣿", "⣯⣿", "⣷⣿",
    "⣿⣾", "⣿⣽", "⣿⣻", "⣿⢿", "⣿⡿", "⣿⣟", "⣿⣯", "⣿⣷")
    $i = 0;
    while ($j -ge 0.1) {
        $symbol =  $symbols[$i]
        Write-Host -NoNewLine "`r$symbol $Label" -ForegroundColor Green
        Start-Sleep -Milliseconds 100
        $i++
        $j = $j - 0.1
        if ($i -eq $symbols.Count){
            $i = 0;
        }
    }
    Write-Host -NoNewLine "`r"
}


function Write-Summary {
    param ($Message)
    Stop-Spinner
    Write-Host -NoNewLine $Message
    Start-Spinner
    # $LAST_SPINNER_PID = $PID
}

# Create dir from OLLAMA_BINARY
$parentDir = (Get-Location).Path
$newPath = Join-Path -Path $parentDir -ChildPath 'bin\ollama'
if (!(Test-Path -Path $newPath -Type Container)) { 
    Write-Host "Creating directory '$newPath'"
    New-Item -ItemType Directory -Path $newPath  # Create dir from OLLAMA_BINARY
} 

$installerPath = Join-Path -Path $newPath -ChildPath $ollamaInstaller

#Function to check if Ollama is running
function Ollama-Needs-Install { 
    Start-Ollama

    $serviceRunning = (Invoke-WebRequest -Uri $localURL -Method Get).Content | ConvertFrom-Json
    $localVersion = $serviceRunning.version
    Write-Host "Local version: $localVersion"
    
    try {
        $downloadUrlResponse = Invoke-WebRequest -Uri $remoteURL -Method Get
    } catch [System.Net.WebException] { 
        if ($_.Exception.Response.StatusCode.value__ -eq 429) { 
            $rateLimitHeaders = @{} 
            foreach ($headerName in @("x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-used", "x-ratelimit-reset")) {
                if ($_.Exception.Response.Headers.ContainsKey($headerName)) {
                    $rateLimitHeaders.Add($headerName, $_.Exception.Response.Headers[$headerName].value)
                }
            }
            
            Write-Host "Error: Rate limiting exceeded. Please try again in $($remoteURL) after `$(join "`", (@($rateLimitHeaders["x-ratelimit-used"])),`) requests made within a time frame of `$(($rateLimitHeaders["x-ratelimit-limit"]))` The rate limit will reset at `$(New-TimeSpan -Seconds $rateLimitHeaders["x-ratelimit-reset"])`" -ForegroundColor Yellow
        } elseif ($_.Exception.Response.StatusCode.value__ -eq 403) {
            Write-Host "Error: Request denied due to rate limiting, please try again later" -ForegroundColor Red
        } else {
            $errorDetails = @{
                Code = $_.Exception.Response.StatusCode.Value__
                Message = $_.ErrorDetails.Message
                Description = $_.StatusDescription
            }

            Write-Host "Error: $($errorDetails.Code) - $($errorDetails.Message)" -ForegroundColor Red
            exit 1
        }
    } 

    $remoteJson = $downloadUrlResponse.Content | ConvertFrom-Json
    $remoteVersion = $remoteJson.tag_name.Substring(1)
    Write-Host "Remote version: $remoteVersion"
    
    if ($localVersion -ne $remoteVersion) {
        Write-Host "Ollama is not running or version mismatch"
        Install-Ollama
    }
    
    $EmojiIcon = [System.Convert]::toInt32("1F600",16)
    Write-Host "Ollama running latest version " -NoNewline
    Write-Host -ForegroundColor Green ([System.Char]::ConvertFromUtf32($EmojiIcon))
}

function Install-Ollama {
    # check if we have the installer already
    $downloadUrlResponse = Invoke-WebRequest -Uri $remoteURL -Method Get
    $downloadUrlJson = $downloadUrlResponse.Content | ConvertFrom-Json
    $dl = 1
    if (Test-Path -Path $installerPath) {
        $fileVersion = (Get-ItemPropertyValue -Path $installerPath -Name VersionInfo).FileVersion
        if ($fileVersion -eq $downloadUrlJson.tag_name.Substring(1)) {
            Write-Host "Ollama installer already exists."
            $dl = 0
        }
    }

    if ($dl -gt 0) {
        Write-Host "Downloading Ollama installer."
        $downloadUrlAsset = $downloadUrlJson.assets | Where-Object {$_.name -eq $ollamaInstaller}
        $downloadUrl = $downloadUrlAsset.browser_download_url
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
    }
    Write-Host "Setting Ollamasetup to executable."
    Get-ChildItem -Path $installerPath | ForEach-Object { $_.IsReadOnly = $false }
    Write-Host "Installing Ollama."
    Start-Process -FilePath $installerPath -ArgumentList $installerArgs
    Ollama-Needs-Install
}

#Function to start AppData\Local\Programs\Ollama\ollama app.exe if it is not running.
function Start-Ollama {
    $ollamaRunning = Get-Process -Name $ollamaApp -ErrorAction SilentlyContinue
    if ($ollamaRunning) {
        Write-Host "Ollama App is running at $($localURL)."
    } else {
        Write-Host "Waiting for Ollama app to start: $($ollamaAppPath)"
        Start-Process -FilePath $ollamaAppPath
        
        Countdown-Timer -Seconds 5
    }
}



# Check if ollama is running by checking the version.  If it is not running, download the latest version and start it.  If it is running, check the local version against the remote version and if they are different, download the latest version and start it.
Ollama-Needs-Install



#exit the script
# exit



# Find the "ollama app.exe" process and shut it down
    # $ollamaRunning = Get-Process -Name "ollama app" -ErrorAction SilentlyContinue
    # if ($ollamaRunning) {
    #     Write-Host "Ollama App is running. Stopping Ollama App."
    #     Stop-Process -Name "ollama app" -Force
    # }

# /VERYSILENT /SP- /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /LOG="install.log" /FORCECLOSEAPPLICATIONS /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /RESART
# AppData\Local\Programs\Ollama\ollama app.exe


# Write-Host "Downloading ollama to $(Get-Location | Split-Path)"
# $serviceRunning = (Invoke-WebRequest -Uri 'http://localhost:11434/api/version' -Method Get).Content | ConvertFrom-Json
# $localVersion = $serviceRunning.version
# $downloadUrlResponse = Invoke-WebRequest -Uri 'https://api.github.com/repos/ollama/ollama/releases/latest' -Method Get
# $remoteJson = $downloadUrlResponse.Content | ConvertFrom-Json
# $remoteVersion = $remoteJson.tag_name.Substring(1)

# if ($null -eq $localVersion) {
#     Write-Host "Ollama is not running"
# } 
# if ($localVersion -eq $remoteVersion) {
#     Write-Host "Ollama running version is $localVersion"
# } else {
#     Stop-Process -Name ollama -Force
#     $downloadUrlAsset = $remoteJson.assets | Where-Object {$_.name -eq "ollama-windows-amd64.exe"}
#     $downloadUrl = $downloadUrlAsset.browser_download_url
#     Invoke-WebRequest -Uri $downloadUrl -OutFile (Join-Path -Path . -ChildPath 'bin\ollama\ollama-windows-amd64.exe')
#     Get-ChildItem -Path (Join-Path -Path . -ChildPath 'bin\ollama\ollama-windows-amd64.exe') | ForEach-Object { $_.IsReadOnly = $false }
#     Start-Process -Name ollama
#     Write-Host "Waiting for Ollama to start..."
#     Start-Sleep -s 5
#     if ((Invoke-WebRequest -Uri 'http://localhost:11434/api/version' -Method Get).Content | ConvertFrom-Json | .version -ne $remoteJson.tag_name.Substring(1)) {
#         Write-Host "Ollama version mismatch. Stopping Ollama."
#     } else {
#         Write-Host "Ollama version match. Continuing..."
#     }
# }

# if ($serviceRunning) {
#     if ($serviceRunning.version -eq $downloadUrlJson.tag_name.Substring(1)) {
#         Write-Host "Ollama running version is $($serviceRunning.version)"
#     } else {
#         Stop-Process -Name ollama -Force
#         $downloadUrlAsset = $downloadUrlJson.assets | Where-Object {$_.name -eq "ollama-windows-amd64.exe"}
#         $downloadUrl = $downloadUrlAsset.browser_download_url
#         Invoke-WebRequest -Uri $downloadUrl -OutFile (Join-Path -Path . -ChildPath 'bin\ollama\ollama-windows-amd64.exe')
#         Get-ChildItem -Path (Join-Path -Path . -ChildPath 'bin\ollama\ollama-windows-amd64.exe') | ForEach-Object { $_.IsReadOnly = $false }
#         Start-Process -Name ollama
#         Write-Host "Waiting for Ollama to start..."
#         Start-Sleep -s 5
#         if ((Invoke-WebRequest -Uri 'http://localhost:11434/api/version' -Method Get).Content | ConvertFrom-Json | .version -ne $downloadUrlJson.tag_name.Substring(1)) {
#             Write-Host "Ollama version mismatch. Stopping Ollama."
#         } else {
#             Write-Host "Ollama version match. Continuing..."
#         }
#     }
# } else {
#     $downloadUrlAsset = $downloadUrlJson.assets | Where-Object {$_.name -eq "ollama-windows-amd64.exe"}
#     $downloadUrl = $downloadUrlAsset.browser_download_url
#     Invoke-WebRequest -Uri $downloadUrl -OutFile (Join-Path -Path . -ChildPath 'bin\ollama\ollama-windows-amd64.exe')
#     Get-ChildItem -Path (Join-Path -Path . -ChildPath 'bin\ollama\ollama-windows-amd64.exe') | ForEach-Object { $_.IsReadOnly = $false }
#     Start-Process -Name ollama
#     Write-Host "Ollama version: $($downloadUrlJson.tag_name)"
# }



# # Make ollama executable
# Get-ChildItem -Path $OLLAMA_BINARY | ForEach-Object { $_.IsReadOnly = $false }

# # Run ollama
# "$OLLAMA_BINARY serve 2>&1 &" > $OLLAMA_PID


# Remove and run litellm-proxy
Get-ChildItem -Path 'litellm-config.yaml' | ForEach-Object { $_.IsReadOnly = $false }


# Function to verify docker is installed and working
function Verify-Docker {
    $dockerVersion = & docker --version
    if ($null -eq $dockerVersion) {
        Write-Host "Docker is not installed. Please install Docker Desktop and try again."
        exit 1
    }
    Write-Host "Docker is installed and running: ($dockerVersion)"
}

# Function to check if a specific docker image is running, and if it is, stop it, and then remove it.
function Remove-Image {
    param ($ImageName)
    $running = & docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $ImageName }
    if ($running) {
        Write-Host "Stopping and removing $ImageName"
        & docker rm -f $running
    }
    Write-Host "($ImageName) is not running"
}

# Function to launch the litellm-proxy docker image

Verify-Docker
Remove-Image -ImageName litellm-proxy

exit


# We should package all this docker stuff up as a docker-compose file and run it from there.
# We should also ensure that any images we need for these are built and available in the local docker registry.


docker run --mount type=bind,source=$(Get-Location),target=/config.yaml,readonly \
    -p 8000:8000 --add-host=host.docker.internal:host-gateway \
    -d --name litellm_proxy ghcr.io/yeahdongcn/litellm-proxy:main --drop_params --config /config.yaml
Write-Host "litellm started"

# Ask for mods config
Read-HotKey -Prompt "Do you want to use predefined mods config? y/n [n]: " -Default 'n'
if ($_.Match('^[Yy]$')) {
    $ModsConfig = Join-Path -Path ~ -ChildPath 'Library\Application\ Support/mods/mods.yml'
    Rename-Item -Path $ModsConfig -NewName (Join-Path -Path ~ -ChildPath 'Library\Application\ Support/mods/mods.yml.backup')
    Copy-Item -Path mods.yml -Destination $ModsConfig
}

# Ask for web UI
Read-HotKey -Prompt "Do you want to start web UI? y/n [n]: " -Default 'n'
if ($_.Match('^[Yy]$')) {
    New-Item -ItemType Directory -Path $(Get-Location | Split-Path) -Name ollama-webui
    docker rm -f ollama-webui 2>&1
    docker run --pull always -d -p 3001:80 -v ollama-webui:/app/backend/data \
        -name ollama-webui --restart always ghcr.io/ollama-webui/ollama-webui:main
    Start-Sleep -Seconds 5
    Start-Process -FilePath http://localhost:3001
}

# Ask for performance statistics monitor
Read-HotKey -Prompt "Do you want to start performance statistics monitor? y/n [n]: " -Default 'n'
if ($_.Match('^[Yy]$')) {
    cd performance-statistics; Get-ChildItem -Path (Get-Build -Show-Bin-Path) | ForEach-Object { $_.IsReadOnly = $false }
    Start-Process -FilePath $COLLECTOR_BINARY -RedirectStandardOutput $OLLAMA_PID -NoNewWindow
    docker rm -f prometheus 2>&1
    docker run -d -p 9000:9000 --name prometheus -v $(Get-Location)prometheus/prometheus.yml:/etc/prometheus/prometheus.yml prom/prometheus
    docker rm -f grafana 2>&1
    docker run -d -p 3000:3000 --name grafana \
        -v $(Get-Location)grafana/datasources:/etc/grafana/provisioning/datasources \
        -v $(Get-Location)grafana/dashboards:/var/lib/grafana/dashboards \
        -e "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/dashboard.json" \
        -e "GF_SECURITY_ADMIN_USER=admin" \
        -e "GF_SECURITY_ADMIN_PASSWORD=admin" \
        -e "GF_AUTH_ANONYMOUS_ENABLED=true" \
        -e "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" \
        grafana/grafana-enterprise
    Start-Sleep -Seconds 5
    Start-Process -FilePath http://localhost:3000
}