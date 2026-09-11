import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { VpnBackgroundTaskService } from '../services/VpnBackgroundTaskService';

const DOMAIN: number = 0x0001;
const TAG: string = 'ClashHarmony';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    VpnBackgroundTaskService.initialize(this.context);
    hilog.info(DOMAIN, TAG, 'EntryAbility created');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility destroyed');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Main page loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Window stage destroyed');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility foreground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility background');
    VpnBackgroundTaskService.startIfVpnRunning();
  }
}
