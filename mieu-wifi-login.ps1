param (
    [Parameter(Position = 0)]
    [string]$Command = "login"
)

$targetSSIDs = @("mieu-mobile-a", "mieu-mobile-g")
$duration = "600"
$language = "ja"
$credFile = Join-Path $PSScriptRoot "credentials.dat"
$sessionFile = Join-Path $PSScriptRoot "session.dat"


function Show-Usage {
    Write-Host "使用法:"
    Write-Host "    " -NoNewline; Write-Host "mieu-wifi-login" -ForegroundColor Green -NoNewline; Write-Host "        ... Wi-Fiログイン(省略形)"
    Write-Host "    " -NoNewline; Write-Host "mieu-wifi-login init" -ForegroundColor Green -NoNewline; Write-Host "   ... 初期設定(学籍番号とパスワードを保存)"
    Write-Host "    " -NoNewline; Write-Host "mieu-wifi-login login" -ForegroundColor Green -NoNewline; Write-Host "  ... Wi-Fiログイン"
    Write-Host "    " -NoNewline; Write-Host "mieu-wifi-login logout" -ForegroundColor Green -NoNewline; Write-Host " ... Wi-Fiログアウト(切断)"
    Write-Host "    " -NoNewline; Write-Host "mieu-wifi-login reset" -ForegroundColor Green -NoNewline; Write-Host "  ... 設定リセット"
}


function Invoke-Init {
    if (Test-Path $credFile) {
        Write-Host "既に初期設定済みです。「" -NoNewline
        Write-Host "mieu-wifi-login reset" -ForegroundColor Green -NoNewline
        Write-Host "」を実行して設定をリセットしてください"
        Show-Usage
        exit 1
    }
    $id = Read-Host "学籍番号"
    $securePass = Read-Host "パスワード" -AsSecureString
    @{
        userid   = $id
        password = ($securePass | ConvertFrom-SecureString)
    } | ConvertTo-Json | Set-Content $credFile
    Write-Host "初期設定が完了しました" -ForegroundColor Blue
}


function Invoke-Login {
    if (-not (Test-Path $credFile)) {
        Write-Host "「" -NoNewline
        Write-Host "mieu-wifi-login init" -ForegroundColor Green -NoNewline
        Write-Host "」を実行して初期設定をしてください"
        Show-Usage
        exit 1
    }

    # SSID確認
    $ssidLine = netsh wlan show interfaces | Select-String "^\s*SSID\s*:\s*(.+)" | Select-Object -First 1
    if (-not $ssidLine) {
        Write-Host "Wi-Fiに接続されていません" -ForegroundColor Red
        exit 1
    }
    $connectedSSID = ($ssidLine -replace "^\s*SSID\s*:\s*", "").Trim()
    if ($connectedSSID -notin $targetSSIDs) {
        Write-Host "SSID不一致: 接続中のSSID '$connectedSSID' は対象外です" -ForegroundColor Red
        exit 1
    }

    # 認証情報読み込み
    $creds = Get-Content $credFile -Raw | ConvertFrom-Json
    $id = $creds.userid
    $pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            ($creds.password | ConvertTo-SecureString)
        )
    )

    try {
        Write-Host "認証URLを取得中..."
        $checkUrl = "http://a.cc.mie-u.ac.jp/"
        $response = Invoke-WebRequest -UseBasicParsing -Uri $checkUrl -TimeoutSec 10

        if ($response.Content -notmatch '(?i)content\s*=\s*["'']1;\s*URL\s*=\s*([^"'']+)["'']') {
            Write-Host "既にログイン済み" -ForegroundColor Blue
            exit 0
        }
        $authUrl = $matches[1]

        if ($authUrl -notmatch 'mgw(\d+)\.cc\.mie-u\.ac\.jp') {
            Write-Host "エラー: mgwサーバー番号を抽出できませんでした" -ForegroundColor Red
            exit 1
        }
        $mgwNumber = $matches[1]
        $srvUrl = "https://mgw$mgwNumber.cc.mie-u.ac.jp/cgi-bin/opengate/opengatesrv.cgi"

        Write-Host "ログイン中..."
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $cookieRes = Invoke-WebRequest -UseBasicParsing -Uri $authUrl -WebSession $session -TimeoutSec 5 | Out-Null

        $res = Invoke-WebRequest -UseBasicParsing -Uri $srvUrl -Method POST -WebSession $session -Body @{
            userid         = $id
            password       = $pass
            duration       = $duration
            language       = $language
            remote_addr    = "0-0-0"
            redirected_url = ""
        }

        if ($res.StatusCode -eq 200) {
            if ($res.Content -match 'href="(http://[^"]+/terminate-[^"]+)"') {
                $disconnectUrl = $matches[1]
                $disconnectUrl | Set-Content $sessionFile
            }
            Write-Host "ログイン成功" -ForegroundColor Blue
        }
        else {
            Write-Host "ログイン失敗: StatusCode = $($res.StatusCode)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "エラー: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}


function Invoke-Logout {
    if (-not (Test-Path $sessionFile)) {
        Write-Host "セッション情報が見つかりません" -ForegroundColor Red
        exit 1
    }
    $disconnectUrl = (Get-Content $sessionFile -Raw).Trim()
    try {
        $res = Invoke-WebRequest -UseBasicParsing -Uri $disconnectUrl -TimeoutSec 10
        Remove-Item $sessionFile -Force
        Write-Host "ログアウト完了" -ForegroundColor Blue
    }
    catch {
        Remove-Item $sessionFile -Force
        Write-Host "エラー: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}


function Invoke-Reset {
    if (-not (Test-Path $credFile)) {
        Write-Host "設定ファイルが存在しません" -ForegroundColor Red
        exit 1
    }
    $ans = Read-Host "設定をリセットしますか? [Y/n]"
    if ($ans -notin @("", "Y", "y", "yes", "Yes", "YES")) {
        exit 1
    }
    Remove-Item $credFile -Force
    if (Test-Path $sessionFile) { Remove-Item $sessionFile -Force }
    Write-Host "リセット完了しました" -ForegroundColor Blue
}


switch ($Command) {
    "init" { Invoke-Init }
    "login" { Invoke-Login }
    "logout" { Invoke-Logout }
    "reset" { Invoke-Reset }
    "help" { Show-Usage }
    default {
        Write-Host "不明なコマンド: $Command" -ForegroundColor Red
        Show-Usage
        exit 1
    }
}
