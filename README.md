# HackSettings

HarmonyOS / OpenHarmony 应用加速服务（App Turbo）探测与开关工具。

- bundleName: `com.example.hacksettings`
- Ability: `EntryAbility`
- 设备类型: `phone` / `tablet` / `2in1`

功能：

- 读取 `settings.application.app_turbo_switch_info`
- 解析 `supportAppInfos`，为每个支持的应用生成一个拨码开关
- 控制全局开关 `settings.application.app_turbo_switch`
- 控制单应用开关 `settings.application.app_turbo_switch_<bundle>`

> 仅用于授权的测试设备。`MANAGE_SETTINGS` 能修改所有非 secure 的 SettingsData，
> 影响面远大于 App Turbo 本身。

## 权限

| 权限 | 级别 | 用途 |
|---|---|---|
| `ohos.permission.MANAGE_SETTINGS` | `system_basic` / `SYSTEM` / `system_grant` | 读写 `USER_PROPERTY` 域，控制 App Turbo |
| `ohos.permission.GET_BUNDLE_INFO` | `normal` / `NORMAL` / `system_grant` | 解析其他应用的 label |

`module.json5` 中声明：

```json5
"requestPermissions": [
  {
    "name": "ohos.permission.MANAGE_SETTINGS",
    "reason": "$string:reason_manage_settings",
    "usedScene": {
      "abilities": ["EntryAbility"],
      "when": "inuse"
    }
  },
  {
    "name": "ohos.permission.GET_BUNDLE_INFO"
  }
]
```

说明：

- `MANAGE_SETTINGS` 是 `system_basic` 权限。普通 APL 的 HAP 仅靠 `requestPermissions`
  正常拿不到；需要签名 profile 的 ACL，且设备信任该签名。
- `ohosign auto` 会从 HAP 的 `module.json` 提取权限并写入 profile 的
  `allowed-acls`。在信任 OpenHarmony Application Root CA 的 log/debug 设备上，
  可以实现 `apl: normal` + ACL 授权；生产设备可能拒绝安装或拒绝授权。
- App Turbo 的键在 `USER_SETTINGSDATA_<userId>`（非 secure），
  不需要 `MANAGE_SECURE_SETTINGS`。

## 数据键

| 键 | 值 | 含义 |
|---|---|---|
| `settings.application.app_turbo_switch` | `"0"` / `"1"` | 全局开关 |
| `settings.application.app_turbo_switch_info` | JSON | 页面初始化读取的聚合状态 |
| `settings.application.app_turbo_switch_<bundle>` | `"0"` / `"1"` | 单应用开关 |

`app_turbo_switch_info` 示例：

```json
{
  "featureSwitch": "1",
  "supportAppInfos": [
    { "cn.wps.office.hap": false }
  ]
}
```

- `featureSwitch`：全局功能状态。
- `supportAppInfos`：数组，每个元素是 `bundleName -> support` 的映射。
- 单应用的实际开关状态在 `settings.application.app_turbo_switch_<bundle>`；
  切换该键后，App Turbo 服务会更新 `supportAppInfos` 中对应项。

## 操作

1. 启动应用，自动读取 `app_turbo_switch_info` 和全局开关。
2. 顶部 `应用加速服务` 是全局拨码开关：
   - ON 写入 `settings.application.app_turbo_switch = "1"`
   - OFF 写入 `"0"`
3. `支持的应用` 列表来自 `supportAppInfos`：
   - 每个子项显示 app label、bundleName、当前 key、support 状态
   - 拨码开关写入 `settings.application.app_turbo_switch_<bundle>`
   - 写入后立即刷新，并在 600ms 后再次刷新，等待服务更新 `supportAppInfos`
4. `刷新` 重新读取全部状态；`清空日志` 清空下方 log。
5. 页面底部显示原始 `app_turbo_switch_info` JSON。

当前设备如果 `supportAppInfos` 只有 WPS，就只显示一行；数组有多项时会自动渲染多行，
不需要改代码。

## 使用的 API

```ts
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError, settings } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
```

| API | 用途 |
|---|---|
| `settings.getValueSync(context, name, defValue, settings.domainName.USER_PROPERTY)` | 读取 SettingsData |
| `settings.setValueSync(context, name, value, settings.domainName.USER_PROPERTY)` | 写入 SettingsData |
| `abilityAccessCtrl.createAtManager().checkAccessTokenSync(tokenId, permission)` | 检查自身 token 权限 |
| `bundleManager.getBundleInfoForSelfSync(...)` | 获取自身 tokenId / uid |
| `bundleManager.getBundleInfoSync(bundleName, ...)` | 通过 bundleName 获取 app label |
| `hilog.info(DOMAIN, TAG, ...)` | 输出日志 |
| `Toggle({ type: ToggleType.Switch, isOn })` | 拨码开关 UI |

读取和写入封装：

```ts
private read(key: string): string {
  return settings.getValueSync(
    this.ctx(), key, '<missing>', settings.domainName.USER_PROPERTY);
}

private write(key: string, value: string): string {
  const ok = settings.setValueSync(
    this.ctx(), key, value, settings.domainName.USER_PROPERTY);
  return `ok=${ok}`;
}
```

## 实现要点

- `parseApps()`：`JSON.parse` 后遍历 `supportAppInfos`，用 `Object.keys` 展开
  `bundleName -> support`，再读取对应的 per-app key。
- `setApp()`：写 `settings.application.app_turbo_switch_<bundle>`，
  然后 `refresh()` + 600ms 延迟刷新。
- `ForEach` 的 key 包含 `bundleName|enabled|supported|keyValue`，
  防止 Toggle 状态变了但行内文本仍显示旧值。
- `labelFor()` 使用 `Map` 缓存 label；WPS 使用内置名称，其他应用走
  `getBundleInfoSync`，失败则回退到 bundleName。
- 日志限制在 12000 字符以内。

## 目录

```text
hacksettings/
├── AppScope/
│   ├── app.json5
│   └── resources/base/element/string.json
├── entry/
│   ├── build-profile.json5
│   └── src/main/
│       ├── module.json5
│       ├── ets/entryability/EntryAbility.ets
│       ├── ets/pages/Index.ets
│       └── resources/...
├── build-profile.json5
├── hvigorfile.ts
├── oh-package.json5
└── README.md
```

`entry/build/`、`.hvigor/`、签名材料不纳入仓库。

## 安全说明

- 这是一个权限探测/测试工具，不应作为普通应用发布。
- `MANAGE_SETTINGS` 能修改所有非 secure 的 SettingsData 键，不仅限于 App Turbo。
- 单应用键可以写入，但 App Turbo 服务是否真正加速该应用，还受
  `supportAppInfos` 和服务内部校验影响。
- 生产环境下，普通 APL + ACL 的签名通常不会被信任；请仅在授权设备上测试。
