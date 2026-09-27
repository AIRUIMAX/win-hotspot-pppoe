# Windows 移动热点 · 一键强开

[![Release](https://img.shields.io/github/v/release/AIRUIMAX/win-hotspot-pppoe?label=release&color=red)](https://github.com/AIRUIMAX/win-hotspot-pppoe/releases/latest)
[![License](https://img.shields.io/github/license/AIRUIMAX/win-hotspot-pppoe)](LICENSE)

解决 **PPPoE「宽带连接」拨号上网时，Windows 设置里的「移动热点」开关永久置灰** 的问题。

跑一遍脚本，手机就能连上电脑热点正常上网。已在 Windows 11 实测跑通。

## 下载

直接拿打包好的压缩包最省事 —— [**下载最新版**](https://github.com/AIRUIMAX/win-hotspot-pppoe/releases/latest)

| 方式 | 说明 |
|------|------|
| `win-hotspot-pppoe-v*.zip`（Release 附件） | **推荐**。解压即得 `start-hotspot.ps1` + `开启热点.cmd` |
| Source code (zip / tar.gz) | 完整源码归档，另含 README 与 LICENSE |
| `git clone` | 想改脚本、提 PR 就用这个 |

---

## 问题背景

用「宽带连接」拨号上网时，Windows 的移动热点会出两类毛病：

1. **开关置灰**——设置面板里的「移动热点」开关点不动，提示「你的电脑无法设置移动热点」。
2. **连上没网**——手动配了 Internet 连接共享（ICS）后，手机能连上 Wi-Fi，但状态栏显示「无互联网连接」。

根本原因是 ICS 只接受**「以太网类」连接**作为共享源，而 PPPoE 拨号连接不在它的白名单里；同时 ICS 建好关系后**不会帮上游连接打开 IP 转发**。

## 解决思路

脚本按下面 4 步依次处理，每一层都在补 Windows 自身的坑：

| # | 步骤 | 作用 |
|---|------|------|
| 1 | WinRT 调 `CreateFromConnectionProfile(...).StartTetheringAsync()` | 绕过设置面板的资格审查，直接把 Wi-Fi Direct 热点拉起来 |
| 2 | 先借「以太网」建立 ICS 共享关系 | 让热点虚拟网卡拿到 `192.168.137.1` 和 DHCP 分配器 |
| 3 | 再把共享源「改」成「宽带连接」 | 改源有效，从零新建无效 |
| 4 | 手动打开「宽带连接」的 IP Forwarding | 补上 ICS 漏掉的上游转发 |

## 使用方法

**要求**：Windows 10 / 11 + **Windows PowerShell 5.1**（不要用 PowerShell 7）+ 管理员权限。

1. 从 [Releases](https://github.com/AIRUIMAX/win-hotspot-pppoe/releases/latest) 下载 `win-hotspot-pppoe-v*.zip` 并解压。
   把 `start-hotspot.ps1` 和 `开启热点.cmd` **放在同一个文件夹**里（启动器靠相对路径找主脚本）。
2. 右键 `开启热点.cmd` → **以管理员身份运行**。
   （直接双击也行，`cmd` 会自动弹 UAC 提权。）
3. 按提示看输出，最后按回车退出。
4. 手机搜索 Wi-Fi，连上电脑热点即可。

> 想在命令行里自己跑，就用完整路径调用 Windows PowerShell，别用 PowerShell 7：
> ```
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-hotspot.ps1
> ```

## 脚本做了什么

运行时会依次输出并执行：

- `[1] 依赖服务` — 检查并按需启动 `icssvc`、`SharedAccess`、`WlanSvc` 三个服务。
- `[2] 加载底层接口` — 加载 WinRT 的 `NetworkInformation` / `NetworkOperatorTetheringManager` 类型。
- `[3] 启动热点` — 依次尝试候选连接配置，最多试 4 个，直到 Wi-Fi Direct 虚拟网卡起来。
- `[4] 配置 Internet 共享` — 若 `192.168.137.1` 还不存在，就重建共享关系（锚点 → 改源）。
- `[5] 打开「宽带连接」的 IP 转发` — 执行 `Set-NetIPInterface -InterfaceAlias "宽带连接" -Forwarding Enabled`。
- `[6] 验证` — 检查网关 IP、DHCP 监听端口 67、以及上游转发状态。

**脚本是幂等的**：如果热点已经在跑、`192.168.137.1` 已存在，会直接跳过重建共享那一步，重复运行没有副作用。

## 如果还是失败

脚本会打印下面这套手动方案，照着做：

1. `Win+R` → 输入 `ncpa.cpl` → 回车。
2. 右键「**以太网**」→ 属性 → **共享** 选项卡 → 勾选「允许其他网络用户通过此计算机的 Internet 连接来连接」→ 家庭网络连接选**热点虚拟网卡** → 确定。
3. 右键「**宽带连接**」→ 属性 → **共享** → 同样勾选，家庭网络连接也选**热点虚拟网卡** → 确定。
4. 断开「宽带连接」，重新拨号一次。

如果脚本提示**找不到可用的锚点连接**，就加一个环回适配器当跳板：

> 设备管理器 → 操作 → 添加过时硬件 → 手动选择 → 网络适配器 → **Microsoft KM-TEST 环回适配器**，
> 装好后把它的名字改成 `loopback`，再重跑脚本。

另外几个常见情况：

- **手机连上仍提示没有互联网**：断开「宽带连接」重新拨号一次，多半就好。
- **热点起不来**：确认 `WlanSvc` 是运行状态，且无线网卡驱动支持 Wi-Fi Direct（`netsh wlan show drivers` 里看「支持的承载网络」）。

## 文件说明

| 文件 | 说明 |
|------|------|
| `start-hotspot.ps1` | 主脚本，全部逻辑都在这里 |
| `开启热点.cmd` | 启动器，负责自动提权 + 用 PowerShell 5.1 调用主脚本 |
| `tools/pack_release.py` | 打包 Release 附件：`python tools/pack_release.py 1.0.0` → `dist/win-hotspot-pppoe-v1.0.0.zip` |
| `开启热点.cmd.lnk` | 本机桌面快捷方式，**未纳入仓库**（含本机绝对路径，无通用价值） |

## 发布新版本

```bash
python tools/pack_release.py 1.1.0
gh release create v1.1.0 dist/win-hotspot-pppoe-v1.1.0.zip \
  --target main --title "v1.1.0 · 简述" --notes-file dist/RELEASE_NOTES_v1.1.0.md --latest
```

## 免责声明

脚本会修改网络适配器的 Internet 连接共享配置和 IP 转发设置，需要管理员权限。请在确认自己理解上述操作的前提下使用。因使用本脚本造成的任何网络配置异常，请自行通过「网络连接」面板还原。

## License

[MIT](LICENSE)

---

> 本项目的代码与文档由 AI 辅助生成，并经过真机实测验证。
