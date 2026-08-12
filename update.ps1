# update.ps1 — 一鍵同步 Sinotrade 官方更新
#
#   用法：在 repo 目錄執行  .\update.ps1
#         想順便推上自己的 fork 就加 -Push
#
# 會依序處理四層：官方程式碼 → 你的 fork → 後端 CLI 版本 → 前端套件

param(
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

function Step($n, $msg) { Write-Host "`n[$n/5] $msg" -ForegroundColor Cyan }
function Ok($msg)       { Write-Host "      $msg" -ForegroundColor Green }
function Warn($msg)     { Write-Host "      $msg" -ForegroundColor Yellow }

# ── 1. 安全檢查：工作區必須乾淨，否則更新會蓋掉你的修改 ──────────────
Step 1 "檢查工作區"
$dirty = git -C $repo status --porcelain
if ($dirty) {
    Warn "有未提交的變更，先 commit 或 stash 再執行："
    $dirty | ForEach-Object { Write-Host "        $_" }
    exit 1
}
Ok "乾淨"

# upstream remote 不存在就補上（新 clone 的機器會缺）
$remotes = git -C $repo remote
if ($remotes -notcontains 'upstream') {
    git -C $repo remote add upstream https://github.com/Sinotrade/shioaji-pro-app.git
    Ok "已新增 upstream remote"
}

# ── 2. 拉官方更新 ────────────────────────────────────────────────
Step 2 "抓取官方更新"
git -C $repo fetch upstream --quiet
$new = git -C $repo rev-list --count HEAD..upstream/main
if ($new -eq 0) {
    Ok "已是最新，沒有新的 commit"
} else {
    Write-Host "      官方有 $new 個新 commit：" -ForegroundColor White
    git -C $repo log --oneline -8 HEAD..upstream/main | ForEach-Object { Write-Host "        $_" }

    # 用 merge 而非 rebase：不改寫既有 commit，推 fork 時不需要 force push
    git -C $repo merge upstream/main --no-edit
    Ok "已合併官方更新"
}

# ── 3. 推到自己的 fork ───────────────────────────────────────────
Step 3 "推送到你的 fork"
if ($Push) {
    git -C $repo push origin main
    Ok "已推送"
} else {
    $ahead = git -C $repo rev-list --count '@{u}..HEAD' 2>$null
    if ($ahead -and $ahead -ne 0) { Warn "有 $ahead 個 commit 未推送（加 -Push 參數即可推）" }
    else { Ok "fork 已同步" }
}

# ── 4. 後端 CLI 版本對齊（最容易漏掉的一層）──────────────────────
Step 4 "檢查後端 CLI 版本"
$want = (Get-Content "$repo\SHIOAJI_VERSION" -Raw).Trim().TrimStart('v')
$have = ''
try {
    $out = & shioaji version 2>&1 | Out-String
    if ($out -match 'version:\s*"?([\d.]+)"?') { $have = $Matches[1] }
} catch { }

if (-not $have) {
    Warn "找不到 shioaji CLI，請先安裝：pip install `"shioaji[speed]`""
} elseif ($have -eq $want) {
    Ok "版本相符（$have）"
} else {
    Warn "版本不符：已安裝 $have，這版需要 $want → 升級中..."
    python -m pip install --upgrade "shioaji[speed]==$want"
    Ok "已升級到 $want"
}

# ── 5. 前端套件 ─────────────────────────────────────────────────
Step 5 "更新前端套件"
pnpm -C $repo install
Ok "完成"

Write-Host "`n更新完畢。啟動方式：" -ForegroundColor Green
Write-Host "  後端： shioaji server start" -ForegroundColor White
Write-Host "  前端： pnpm dev" -ForegroundColor White
