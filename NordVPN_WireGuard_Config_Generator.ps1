param (
    [string]$ApiToken = 'API_KEY',
    [string]$Dns = '1.1.1.1',
    [string]$Servers = '3'

)

# Show help if no parameters were passed
if ($PSBoundParameters.Count -eq 0) {
    Write-Host "#################################################" -ForegroundColor White
    Write-Host "# WireGuard Config Generator (PowerShell)       #" -ForegroundColor White
    Write-Host "# Maxi                                          #" -ForegroundColor White
    Write-Host "#                                               #" -ForegroundColor White
    Write-Host "# Parameters:                                   #" -ForegroundColor Green
    Write-Host "#   -ApiToken [string]   : NordVPN API Token    #" -ForegroundColor Green
    Write-Host "#                          (default: 'API_KEY') #" -ForegroundColor Green
    Write-Host "#   -Dns [string]        : DNS server address   #" -ForegroundColor Green
    Write-Host "#                          (default: '1.1.1.1') #" -ForegroundColor Red
    Write-Host "#   -Servers [string]    : Servers to get       #" -ForegroundColor Red
    Write-Host "#                          (default: '3')       #" -ForegroundColor Red
    Write-Host "#################################################" -ForegroundColor Red
    Write-Host " "
    Write-Host "NordVPN Access Token Instructions :" -ForegroundColor Gray
    Write-Host "https://support.nordvpn.com/hc/en-us/articles/20286980309265-How-to-use-a-token-with-NordVPN-on-Linux" -ForegroundColor Gray
}


if ($ApiToken -eq 'API_KEY') {exit}

$CredentialsUrl = "https://api.nordvpn.com/v1/users/services/credentials"
$RecommendationsUrl = "https://api.nordvpn.com/v1/servers/recommendations?filters[servers_technologies][identifier]=wireguard_udp&limit=$Servers"

function Terminate-Program {
    param ([string]$Message)
    Write-Host $Message -ForegroundColor Red
    Write-Host "Program is terminating!" -ForegroundColor Yellow
    exit 1
}

$EncodedToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("token:$ApiToken"))
$AuthHeaders = @{ Authorization = "Basic $EncodedToken" }

function Fetch-Data {
    param (
        [string]$Url,
        [hashtable]$Headers
    )
    try {
        return Invoke-RestMethod -Uri $Url -Headers $Headers
    } catch {
        Terminate-Program "Failed to fetch data: $_"
    }
}

$CredentialsResponse = Fetch-Data -Url $CredentialsUrl -Headers $AuthHeaders
$PrivateKey = $CredentialsResponse.nordlynx_private_key
if (-not $PrivateKey) {
    Terminate-Program "Credentials failed to retrieve. Response: $($CredentialsResponse | ConvertTo-Json -Depth 5)"
}
Write-Host "Successfully retrieved private key from NordVPN."

$RecommendedServers = Fetch-Data -Url $RecommendationsUrl -Headers @{}
if (-not $RecommendedServers -or $RecommendedServers.Count -eq 0) {
    Terminate-Program "No recommended servers received from API."
}

# Config template
$ConfigTemplate = @"
###############################################
# WireGuard Config Generator PS Fork // Maxi  #
# Edit as needed for DNS, Allowed IP's etc... #
# PROVIDED “AS IS”                            #
###############################################
[Interface]
Address = 10.5.0.2/32
PrivateKey = {private_key}
DNS = {dns}

[Peer]
PublicKey = {public_key}
Endpoint = {server_ip}:51820
AllowedIPs = 0.0.0.0/0
"@

foreach ($Server in $RecommendedServers) {
    $ServerName = $Server.name
    $ServerIP = $Server.station
    $WireGuardTech = $Server.technologies | Where-Object { $_.identifier -eq "wireguard_udp" }

    if (-not $ServerName -or -not $WireGuardTech) {
        Write-Host "Skipping server: Missing name or WireGuard UDP support." -ForegroundColor DarkYellow
        continue
    }

    $PublicKey = ($WireGuardTech.metadata | Where-Object { $_.name -eq "public_key" }).value
    if (-not $PublicKey) {
        Write-Host "Skipping server: No public key found." -ForegroundColor DarkYellow
        continue
    }

    $SafeServerName = $ServerName -replace '[\\/:*?"<>|]', '' -replace '\s+', '_'
    $OutputConfigPath = "NordVPN_WireguardConfig_$SafeServerName.conf"

    $Config = $ConfigTemplate -replace '{private_key}', $PrivateKey `
                              -replace '{public_key}', $PublicKey `
                              -replace '{server_ip}', $ServerIP `
                              -replace '{dns}', $Dns

    Set-Content -Path $OutputConfigPath -Value $Config
    Write-Host "✅ Created config: $OutputConfigPath" -ForegroundColor White
}

Write-Host "`nAll configs generated." -ForegroundColor Blue
