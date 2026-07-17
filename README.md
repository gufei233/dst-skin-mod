# DST Skin Mod

一个《饥荒联机版》皮肤模组，通过本地 `custom_` 皮肤定义同步和加载官方皮肤资源。

当前版本：`V6.2.0`

## 功能

- 支持角色、物品、服装及其他皮肤资源。
- 使用独立的 `custom_` 命名空间加载皮肤。
- 持续同步《饥荒联机版》官方皮肤数据和动画资源。

## 安装

### Windows / Steam 手动安装

1. 在 Steam 库中右键《饥荒联机版》，选择“管理” -> “浏览本地文件”。
2. 打开游戏目录中的 `mods` 文件夹。常见位置是：

   ```text
   C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods
   ```

   如果游戏安装在其他 Steam 库，请以“浏览本地文件”打开的位置为准。

3. 下载本仓库的 ZIP 源码并解压，将目录命名为 `dst-skin-mod`，放入 `mods` 文件夹：

   ```text
   Don't Starve Together\mods\dst-skin-mod\
   ```

4. 检查目录层级。下面两个文件必须直接位于模组目录中，不能再多套一层文件夹：

   ```text
   Don't Starve Together\mods\dst-skin-mod\modmain.lua
   Don't Starve Together\mods\dst-skin-mod\modinfo.lua
   ```

5. 启动游戏，在主菜单进入“模组/Mods”，找到本模组并启用，然后应用更改。
6. 创建或编辑世界时，在“模组”页确认本模组已启用，再启动世界。

本模组设置了 `all_clients_require_mod = true`，联机时服务端和客户端都需要安装并启用。

### 专用服务器

1. 将完整的 `dst-skin-mod` 文件夹复制到专用服务器安装目录的 `mods` 文件夹。
2. 在服务器存档的每个分片目录中配置 `modoverrides.lua`。同时使用地面和洞穴时，`Master` 与 `Caves` 都需要配置：

   ```lua
   return {
       ["dst-skin-mod"] = { enabled = true },
   }
   ```

3. 确保加入服务器的客户端安装的是同一版本。更新模组后应同时替换服务端与客户端文件。

### 常见问题

- 游戏中看不到模组：优先检查是否出现了 `dst-skin-mod\dst-skin-mod\modmain.lua` 这种多套一层目录的情况。
- 联机提示模组不一致：确认服务端和所有客户端使用相同提交或版本。
- 游戏更新后贴图、特效异常或崩溃：先更新模组；排查游戏本身问题时暂时禁用所有模组后重新测试。
- 删除模组：关闭游戏后删除 `mods\dst-skin-mod`，并从对应世界的模组设置或 `modoverrides.lua` 中移除配置。

## 更新检查

在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\compare_missing_skins.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate_skin_update.ps1
```

完整的皮肤同步、资源处理和验证流程见 [AI_UPDATE_GUIDE.md](./AI_UPDATE_GUIDE.md)。

## 免责声明

- 本项目是非官方社区项目，与 Klei Entertainment、Steam 或 Valve 没有隶属、授权或背书关系。
- 《饥荒联机版》名称、商标、游戏代码、美术及皮肤资源的权利归其各自权利人所有。
- 本项目仅供个人学习、研究和兼容性测试。使用者应自行确认其使用及分发方式符合 Klei 内容规范、Steam 订户协议及所在地法律。
- 不得利用本项目绕过皮肤、物品掉落、DLC、付费内容或其他产品权益，也不要在未取得必要权利或许可时重新发布到 Steam 创意工坊或其他平台。
- 模组可能因游戏更新、其他模组冲突或安装环境差异而失效，并可能造成崩溃或存档异常。使用前请备份存档；使用风险由使用者自行承担，不提供任何明示或默示保证。
- Klei 官方仅为未修改的游戏提供技术支持。报告游戏问题前，应先禁用模组并确认问题仍能复现。

## 官方参考

- [Klei：下载和启用模组](https://support.klei.com/hc/en-us/articles/360029556452-How-do-I-download-and-activate-mods-for-Don-t-Starve)
- [Klei：《饥荒》与《饥荒联机版》模组规范](https://support.klei.com/hc/en-us/articles/360029555992-Modding-Don-t-Starve-and-Don-t-Starve-Together)
- [Klei：《饥荒联机版》故障排查](https://support.klei.com/hc/en-us/articles/360029555352-Dont-Starve-Together-Troubleshooting-Guide)
- [Klei 论坛：专用服务器 `modoverrides.lua`](https://forums.kleientertainment.com/forums/topic/52557-how-to-get-mods-working-dedicated-server-with-modoverrideslua-file/)
