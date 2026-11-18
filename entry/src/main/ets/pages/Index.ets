import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError, settings } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'HackSettings';
const MANAGE_SETTINGS: Permissions = 'ohos.permission.MANAGE_SETTINGS';
const MAIN_KEY: string = 'settings.application.app_turbo_switch';
const INFO_KEY: string = 'settings.application.app_turbo_switch_info';
const APP_KEY_PREFIX: string = 'settings.application.app_turbo_switch_';
const MISSING: string = '<missing>';

class AppItem {
  bundleName: string;
  label: string;
  enabled: boolean;
  supported: boolean;
  keyValue: string;

  constructor(bundleName: string, label: string, enabled: boolean, supported: boolean, keyValue: string) {
    this.bundleName = bundleName;
    this.label = label;
    this.enabled = enabled;
    this.supported = supported;
    this.keyValue = keyValue;
  }
}

interface TurboInfo {
  featureSwitch: string;
  supportAppInfos: Array<Record<string, boolean>>;
}

@Entry
@ComponentV2
struct Index {
  @Local mainEnabled: boolean = false;
  @Local appItems: AppItem[] = [];
  @Local output: string = '';
  @Local granted: string = 'unknown';
  @Local tokenId: number = -1;
  @Local rawInfo: string = '';
  private labelCache: Map<string, string> = new Map<string, string>();

  aboutToAppear(): void {
    this.checkPermission();
    this.refresh('init');
  }

  private log(line: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', line);
    console.info('HackSettings ' + line);
    this.output = this.output + line + '\n';
    if (this.output.length > 12000) {
      this.output = this.output.substring(this.output.length - 12000);
    }
  }

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private read(key: string): string {
    try {
      return settings.getValueSync(this.ctx(), key, MISSING, settings.domainName.USER_PROPERTY);
    } catch (e) {
      const err = e as BusinessError;
      return `ERR(${err.code}:${err.message})`;
    }
  }

  private write(key: string, value: string): string {
    try {
      const ok: boolean = settings.setValueSync(this.ctx(), key, value, settings.domainName.USER_PROPERTY);
      return `ok=${ok}`;
    } catch (e) {
      const err = e as BusinessError;
      return `ERR(${err.code}:${err.message})`;
    }
  }

  private checkPermission(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.tokenId = info.appInfo.accessTokenId;
      const at = abilityAccessCtrl.createAtManager();
      const status = at.checkAccessTokenSync(this.tokenId, MANAGE_SETTINGS);
      this.granted = status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ? 'GRANTED' : 'DENIED';
      this.log(`token=${this.tokenId} MANAGE_SETTINGS=${this.granted}`);
    } catch (e) {
      const err = e as BusinessError;
      this.granted = 'ERROR';
      this.log(`permission check failed: ${err.code} ${err.message}`);
    }
  }

  private labelFor(bundleName: string): string {
    const cached: string | undefined = this.labelCache.get(bundleName);
    if (cached !== undefined) {
      return cached;
    }
    let label: string = bundleName;
    if (bundleName === 'cn.wps.office.hap') {
      label = 'WPS Office';
    } else if (bundleName === 'cn.wps.office.hap.ent.huawei') {
      label = 'WPS Office 企业版';
    } else {
      try {
        const info = bundleManager.getBundleInfoSync(
          bundleName, bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
        const bundleLabel: string = info.appInfo.label;
        if (bundleLabel && bundleLabel.length > 0 && bundleLabel.indexOf('$') !== 0) {
          label = bundleLabel;
        }
      } catch (e) {
        // Bundle info may be restricted; fall back to the bundle name.
      }
    }
    this.labelCache.set(bundleName, label);
    return label;
  }

  private parseApps(info: string): AppItem[] {
    const result: AppItem[] = [];
    if (!info || info.indexOf('{') < 0 || info.indexOf('supportAppInfos') < 0) {
      return result;
    }
    try {
      const raw = JSON.parse(info) as TurboInfo;
      const list = raw.supportAppInfos;
      if (!list) {
        return result;
      }
      for (const entry of list) {
        const bundles: string[] = Object.keys(entry);
        for (const bundleName of bundles) {
          const key: string = APP_KEY_PREFIX + bundleName;
          const value: string = this.read(key);
          const supported: boolean = entry[bundleName] === true;
          const enabled: boolean = value === '1';
          result.push(new AppItem(bundleName, this.labelFor(bundleName), enabled, supported, value));
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      this.log(`parse turbo info failed: ${err.code} ${err.message}`);
    }
    return result;
  }

  private refresh(tag: string): void {
    const main: string = this.read(MAIN_KEY);
    this.mainEnabled = main === '1';
    const info: string = this.read(INFO_KEY);
    this.rawInfo = info;
    this.appItems = this.parseApps(info);
    this.log(`[${tag}] main=${main} apps=${this.appItems.length}`);
  }

  private scheduleSync(): void {
    setTimeout(() => {
      this.refresh('sync');
    }, 600);
  }

  private setMain(isOn: boolean): void {
    this.mainEnabled = isOn;
    const ret: string = this.write(MAIN_KEY, isOn ? '1' : '0');
    this.log(`main -> ${isOn ? '1' : '0'} ${ret}`);
    this.refresh('main');
    this.scheduleSync();
  }

  private setApp(item: AppItem, isOn: boolean): void {
    const key: string = APP_KEY_PREFIX + item.bundleName;
    const ret: string = this.write(key, isOn ? '1' : '0');
    this.log(`${item.bundleName} -> ${isOn ? '1' : '0'} ${ret}`);
    this.refresh('app');
    this.scheduleSync();
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('HackSettings')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontFamily('HarmonyHeiTi')
          Text(`MANAGE_SETTINGS: ${this.granted}  tokenId=${this.tokenId}`)
            .fontSize(12)
            .fontColor('#666')
            .fontFamily('HarmonyHeiTi')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('刷新')
          .fontSize(14)
          .fontFamily('HarmonyHeiTi')
          .onClick(() => {
            this.refresh('manual');
          })
      }
      .width('100%')
      .margin({ top: 16, bottom: 12 })

      Row() {
        Column() {
          Text('应用加速服务')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontFamily('HarmonyHeiTi')
          Text(MAIN_KEY)
            .fontSize(10)
            .fontColor('#888')
            .fontFamily('HarmonyHeiTi')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.mainEnabled })
          .onChange((isOn: boolean) => {
            this.setMain(isOn);
          })
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#FFFFFF')
      .borderRadius(14)
      .margin({ bottom: 12 })

      Row() {
        Text(`支持的应用 (${this.appItems.length})`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily('HarmonyHeiTi')
        Blank()
        Button('清空日志')
          .fontSize(13)
          .fontFamily('HarmonyHeiTi')
          .onClick(() => {
            this.output = '';
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.appItems.length === 0) {
        Text('app_turbo_switch_info.supportAppInfos 为空')
          .fontSize(14)
          .fontColor('#999')
          .width('100%')
          .margin({ top: 8, bottom: 8 })
      } else {
        List({ space: 8 }) {
          ForEach(this.appItems, (item: AppItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.label)
                    .fontSize(16)
                    .fontFamily('HarmonyHeiTi')
                  Text(`${item.bundleName}  key=${item.keyValue}  support=${item.supported}`)
                    .fontSize(10)
                    .fontColor('#888')
                    .fontFamily('HarmonyHeiTi')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: item.enabled })
                  .onChange((isOn: boolean) => {
                    this.setApp(item, isOn);
                  })
              }
              .width('100%')
              .padding(14)
              .backgroundColor('#FFFFFF')
              .borderRadius(14)
            }
          }, (item: AppItem) => `${item.bundleName}|${item.enabled}|${item.supported}|${item.keyValue}`)
        }
        .width('100%')
        .height(300)
        .margin({ bottom: 8 })
      }

      Text(`raw: ${this.rawInfo}`)
        .fontSize(10)
        .fontColor('#999')
        .fontFamily('HarmonyHeiTi')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ bottom: 8 })

      TextArea({ text: this.output, placeholder: 'log' })
        .width('100%')
        .layoutWeight(1)
        .fontSize(11)
        .fontFamily('HarmonyHeiTi')
        .backgroundColor('#F2F2F2')
        .borderRadius(10)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 24 })
  }
}
