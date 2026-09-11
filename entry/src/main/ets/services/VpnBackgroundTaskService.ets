import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'VpnBackgroundTask';
const BUNDLE_NAME: string = 'io.github.clashharmony.app';
const ENTRY_ABILITY_NAME: string = 'EntryAbility';

export class VpnBackgroundTaskService {
  private static context: common.UIAbilityContext | undefined = undefined;
  private static vpnRunning: boolean = false;
  private static started: boolean = false;
  private static starting: boolean = false;

  static initialize(context: common.UIAbilityContext): void {
    VpnBackgroundTaskService.context = context;
  }

  static async setVpnRunning(running: boolean): Promise<void> {
    VpnBackgroundTaskService.vpnRunning = running;
    if (!running) {
      await VpnBackgroundTaskService.stop();
    }
  }

  static async startIfVpnRunning(): Promise<boolean> {
    if (!VpnBackgroundTaskService.vpnRunning) {
      return false;
    }
    if (VpnBackgroundTaskService.started || VpnBackgroundTaskService.starting) {
      return true;
    }
    const context: common.UIAbilityContext | undefined = VpnBackgroundTaskService.context;
    if (!context) {
      hilog.error(DOMAIN, TAG, 'Unable to start VPN background task: UIAbility context is unavailable');
      return false;
    }

    VpnBackgroundTaskService.starting = true;
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: BUNDLE_NAME,
            abilityName: ENTRY_ABILITY_NAME
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const notificationWantAgent: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        notificationWantAgent
      );
      VpnBackgroundTaskService.started = true;
      hilog.info(DOMAIN, TAG, 'VPN data-transfer background task started');

      if (!VpnBackgroundTaskService.vpnRunning) {
        await VpnBackgroundTaskService.stop();
        return false;
      }
      return true;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(
        DOMAIN,
        TAG,
        'Failed to start VPN background task, code=%{public}d message=%{public}s',
        error.code,
        error.message
      );
      return false;
    } finally {
      VpnBackgroundTaskService.starting = false;
    }
  }

  static async stop(): Promise<void> {
    const context: common.UIAbilityContext | undefined = VpnBackgroundTaskService.context;
    if (!VpnBackgroundTaskService.started || !context) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      VpnBackgroundTaskService.started = false;
      hilog.info(DOMAIN, TAG, 'VPN data-transfer background task stopped');
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(
        DOMAIN,
        TAG,
        'Failed to stop VPN background task, code=%{public}d message=%{public}s',
        error.code,
        error.message
      );
    }
  }
}
