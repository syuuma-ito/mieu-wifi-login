# mieu-wifi-login

三重大学の学内WiFiに自動ログインするスクリプト

## セットアップ

```powershell
.\mieu-wifi-login.ps1 init
```

学籍番号とパスワードを入力すると、暗号化して `credentials.dat` に保存します。

## 使い方

```powershell
# ログイン（引数省略でもOK）
.\mieu-wifi-login.ps1
.\mieu-wifi-login.ps1 login

# ログアウト（切断）
.\mieu-wifi-login.ps1 logout

# 設定リセット
.\mieu-wifi-login.ps1 reset

# ヘルプ
.\mieu-wifi-login.ps1 help
```
