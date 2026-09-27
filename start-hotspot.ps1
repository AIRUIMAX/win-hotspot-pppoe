# ============================================================
#  Windows 移动热点 —— 一键强开（PPPoE 拨号环境专用）   (V7)
#
#  适用症状：
#    · 用「宽带连接」(PPPoE) 拨号上网时，「移动热点」开关永久置灰
#    · 手动配 Internet 共享后，手机连上但提示"无互联网连接"
#
#  已实测跑通的完整链路（2026-09-25）：
#    1) WinRT 调 CreateFromConnectionProfile(...).StartTetheringAsync()
#       绕过设置面板的资格审查，直接把 Wi-Fi Direct 热点拉起来
#    2) ICS 只接受"以太网类"连接作为共享源 → 先借「以太网」建立关系，
#       让热点虚拟网卡拿到 192.168.137.1 与 DHCP 分配器
#    3) 再把共享源"改"成「宽带连接」（改源有效，从零建无效）
#    4) ICS 会漏掉上游转发 → 手动把「宽带连接」的 IP Forwarding 打开
#
#  要求：Windows PowerShell 5.1（不要用 PowerShell 7）+ 管理员身份
# ============================================================

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Say($t) { Write-Host $t }

function Get-VapName {
    $a = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
           Where-Object { $_.InterfaceDescription -like '*Wi-Fi Direct*' -and $_.Status -eq 'Up' })
    if ($a.Count -gt 0) { return [string]$a[0].Name }
    return ''
}

function Test-HotspotIP {
    $h = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -eq '192.168.137.1' })
    return ($h.Count -gt 0)
}

Say "=================================================="
Say " Windows 移动热点 · 一键强开  (V7)"
Say "=================================================="

# ---------- 1. 管理员 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Say ""
    Say "[x] 需要管理员权限。请右键「开启热点.cmd」-> 以管理员身份运行。"
    Read-Host "按回车退出"
    exit 1
}

# ---------- 2. 服务 ----------
Say ""
Say "[1] 依赖服务"
foreach ($svc in @('icssvc', 'SharedAccess', 'WlanSvc')) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($null -eq $s) { Say ("    - " + $svc + " : 不存在") }
    else {
        Say ("    - " + $svc + " : " + $s.Status)
        if ($s.Status -ne 'Running') {
            try { Start-Service -Name $svc; Say "      -> 已启动" } catch { Say "      -> 启动失败" }
        }
    }
}

# ---------- 3. WinRT ----------
Say ""
Say "[2] 加载底层接口"
try {
    $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
    $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
    Say "    OK"
} catch {
    Say "[x] 无法加载 WinRT（请用它自带的「开启热点.cmd」以 PowerShell 5.1 运行）"
    Read-Host "按回车退出"
    exit 1
}

# ---------- 4. 强开热点 ----------
Say ""
Say "[3] 启动热点"
$vap = Get-VapName
if ($vap -ne '') {
    Say ("    热点已在运行，网卡: " + $vap)
} else {
    $profiles = @()
    try { $profiles = @([Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles()) } catch { }
    $inet = $null
    try { $inet = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile() } catch { }
    if ($inet) { Say ("    Internet 连接 = " + $inet.ProfileName) }

    $pri = @()
    if ($inet) { $pri += $inet }
    foreach ($key in @('以太网', 'Ethernet', 'loopback')) {
        foreach ($p in $profiles) { if ($p.ProfileName -eq $key) { $pri += $p } }
    }
    foreach ($p in $profiles) { $pri += $p }

    $tried = @{}
    $list = @()
    foreach ($c in $pri) {
        if (-not $tried.ContainsKey($c.ProfileName)) { $tried[$c.ProfileName] = 1; $list += $c }
    }

    $n = 0
    foreach ($c in $list) {
        if ($n -ge 4) { break }
        $n++
        Say ("    候选 " + $n + ": " + $c.ProfileName)
        $tm = $null
        try {
            $tm = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($c)
        } catch { continue }
        if ($null -eq $tm) { continue }

        $st = ''
        try { $st = [string]$tm.TetheringOperationalState } catch { $st = 'On' }
        if ($st -ne 'On') {
            try { $null = $tm.StartTetheringAsync() } catch { continue }
        }
        for ($i = 1; $i -le 5; $i++) {
            Start-Sleep -Seconds 2
            $vn = Get-VapName
            if ($vn -ne '') { Say ("        -> 热点网卡已就绪: " + $vn); break }
        }
        if ((Get-VapName) -ne '') { break }
    }
    $vap = Get-VapName
    if ($vap -eq '') {
        Say "[x] 热点没能起来。仍失败就加一个环回适配器（设备管理器 -> 操作 ->"
        Say "    添加过时硬件 -> 手动选择 -> 网络适配器 -> Microsoft KM-TEST 环回"
        Say "    适配器），改名 loopback 后重跑。"
        Read-Host "按回车退出"
        exit 1
    }
}
$target = $vap
Say ("    热点虚拟网卡: " + $target)
Start-Sleep -Seconds 2

# ---------- 5. 配共享（只在需要时） ----------
Say ""
Say "[4] 配置 Internet 共享"
if (Test-HotspotIP) {
    Say "    虚拟网卡已有 192.168.137.1，跳过（配置仍有效）"
} else {
    Say "    需要重建共享关系（关键步骤：先用以太网建关系，再改源到宽带连接）"
    $mgr = $null
    try { $mgr = New-Object -ComObject HNetCfg.HNetShare } catch { Say "    [x] 无法创建共享管理对象" }

    if ($null -ne $mgr) {
        $conns = @()
        try { foreach ($cn in $mgr.EnumEveryConnection) { $conns += $cn } } catch { }
        $names = @()
        foreach ($cn in $conns) {
            $nm = ''
            try { $nm = [string]$mgr.NetConnectionProps($cn).Name } catch { $nm = '' }
            $names += $nm
        }
        Say ("    ICS 可见连接数: " + $conns.Count)

        function Find-Conn([string]$want) {
            for ($i = 0; $i -lt $conns.Count; $i++) {
                if ($names[$i] -eq $want) { return $conns[$i] }
            }
            return $null
        }

        function Pair-Sharing($srcConn, $tgtConn) {
            try {
                $sc = $mgr.INetSharingConfigurationForINetConnection($srcConn)
                $tc = $mgr.INetSharingConfigurationForINetConnection($tgtConn)
                if ($sc.SharingEnabled) { $sc.DisableSharing() }
                if ($tc.SharingEnabled) { $tc.DisableSharing() }
                $sc.EnableSharing(0)
                $tc.EnableSharing(1)
                return 'OK'
            } catch { return '失败' }
        }

        # 选一个"以太网类"的锚点连接
        $anchorName = ''
        foreach ($nm in @('以太网', 'Ethernet', 'WLAN', 'Wi-Fi')) {
            if ($names -contains $nm) { $anchorName = $nm; break }
        }
        if ($anchorName -eq '') {
            for ($i = 0; $i -lt $names.Count; $i++) {
                if ($names[$i] -notlike '*宽带*' -and $names[$i] -ne $target -and $names[$i] -notlike '*VMnet*') {
                    $anchorName = $names[$i]; break
                }
            }
        }
        Say ("    锚点连接: " + $anchorName)

        $aConn = $null; $tConn = $null; $bConn = $null
        if ($anchorName -ne '') { $aConn = Find-Conn $anchorName }
        $tConn = Find-Conn $target
        if ($names -contains '宽带连接') { $bConn = Find-Conn '宽带连接' }

        if ($null -ne $aConn -and $null -ne $tConn) {
            $r1 = Pair-Sharing $aConn $tConn
            Say ("    [1/2] " + $anchorName + " -> " + $target + " : " + $r1)
            Start-Sleep -Seconds 3
            if (Test-HotspotIP) {
                Say "          -> 192.168.137.1 已出现"
                if ($null -ne $bConn) {
                    $r2 = Pair-Sharing $bConn $tConn
                    Say ("    [2/2] 改源为 宽带连接 : " + $r2)
                    Start-Sleep -Seconds 2
                }
            } else {
                Say "          -> 未出现 192.168.137.1，请手动配（见文末）"
            }
        } else {
            Say "    [x] 找不到锚点连接或热点网卡，请手动配"
        }
    }
}

# ---------- 6. 打开上游 IP 转发（关键补丁） ----------
Say ""
Say "[5] 打开「宽带连接」的 IP 转发"
try {
    Set-NetIPInterface -InterfaceAlias "宽带连接" -Forwarding Enabled -ErrorAction Stop
    $f = (Get-NetIPInterface -InterfaceAlias "宽带连接" -AddressFamily IPv4 -ErrorAction SilentlyContinue).Forwarding
    Say ("    Forwarding = " + $f)
} catch {
    Say "    [x] 设置失败，请手动执行（管理员 PowerShell）："
    Say "        Set-NetIPInterface -InterfaceAlias `"宽带连接`" -Forwarding Enabled"
}

# ---------- 7. 验证 ----------
Say ""
Say "[6] 验证"
Start-Sleep -Seconds 2
$ok = $true

$h = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq '192.168.137.1' })
if ($h.Count -gt 0) { Say "    [OK] 热点网关 192.168.137.1 正常" } else { Say "    [x] 缺少 192.168.137.1"; $ok = $false }

$d = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq '192.168.137.1' -and $_.LocalPort -eq 67 })
if ($d.Count -gt 0) { Say "    [OK] DHCP 分配器在监听" } else { Say "    [!] 没看到 DHCP 分配器" }

$fw = (Get-NetIPInterface -InterfaceAlias "宽带连接" -AddressFamily IPv4 -ErrorAction SilentlyContinue).Forwarding
Say ("    宽带连接转发: " + $fw)

Say ""
if ($ok) {
    Say "手机现在可以连热点上网了。"
    Say "若手机仍提示没有互联网：断开「宽带连接」重新拨号一次，再试。"
} else {
    Say "共享没配好。热点已经开着，手动补："
    Say "  Win+R -> ncpa.cpl"
    Say "  1) 右键「以太网」-> 属性 -> 共享 -> 勾选 + 家庭网络连接选「" + $target + "」-> 确定"
    Say "  2) 右键「宽带连接」-> 属性 -> 共享 -> 勾选 + 选「" + $target + "」-> 确定"
    Say "  3) 断开「宽带连接」重新拨号"
}
Say ""
Read-Host "按回车退出"
