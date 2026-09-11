import { Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import nativeCore from 'libentry.so';
import { ControllerStatus, MihomoControllerService } from './MihomoControllerService';
import { VpnBackgroundTaskService } from './VpnBackgroundTaskService';

const DOMAIN: number = 0x0001;
const TAG: string = 'VpnWatchdog';
const BUNDLE_NAME: string = 'io.github.clashharmony.app';
const VPN_ABILITY_NAME: string = 'ClashVpnExtensionAbility';
const WATCHDOG_INTERVAL_MS: number = 2000;
const WATCHDOG_START_GRACE_MS: number = 15000;
const WATCHDOG_FAILURE_THRESHOLD: number = 2;
const WATCHDOG_RESTART_COOLDOWN_MS: number = 10000;
function createVpnWant(configPath?: string): Want {
  const want: Want = {
    bundleName: BUNDLE_NAME,
    abilityName: VPN_ABILITY_NAME
  };
  if (configPath && configPath.length > 0) {
    want.parameters = {
      configPath: configPath
    };
  }
  return want;
}

export class VpnService {
  private static watchdogIntervalId: number | undefined = undefined;
  private static watchdogChecking: boolean = false;
  private static restartInFlight: boolean = false;
  private static shouldRun: boolean = false;
  private static configPath: string = '';
  private static consecutiveFailures: number = 0;
  private static watchdogGraceUntil: number = 0;

  static async start(configPath: string): Promise<boolean> {
    await VpnBackgroundTaskService.setVpnRunning(true);
    VpnService.shouldRun = true;
    VpnService.configPath = configPath;
    VpnService.consecutiveFailures = 0;
    VpnService.watchdogGraceUntil = Date.now() + WATCHDOG_START_GRACE_MS;
    try {
      const result = await Promise.race([
        vpnExtension.startVpnExtensionAbility(createVpnWant(configPath)),
        VpnService.timeout(5000)
      ]);
      if (result === 'timeout') {
        VpnService.shouldRun = false;
        await VpnBackgroundTaskService.setVpnRunning(false);
        return false;
      }
      // Request the continuous task after the VPN extension process exists,
      // while the UIAbility is still safely in the foreground.
      await VpnBackgroundTaskService.startIfVpnRunning();
      VpnService.startWatchdog();
      return true;
    } catch (err) {
      VpnService.shouldRun = false;
      await VpnBackgroundTaskService.setVpnRunning(false);
      return false;
    }
  }

  static async stop(): Promise<boolean> {
    VpnService.shouldRun = false;
    VpnService.stopWatchdog();
    await VpnBackgroundTaskService.setVpnRunning(false);
    try {
      const result = await Promise.race([
        vpnExtension.stopVpnExtensionAbility(createVpnWant()),
        VpnService.timeout(3000)
      ]);
      if (result === 'timeout') {
        return false;
      }
      return true;
    } catch (err) {
      return false;
    }
  }

  private static timeout(ms: number): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void) => {
      setTimeout(() => { resolve('timeout') }, ms);
    });
  }

  private static startWatchdog(): void {
    if (VpnService.watchdogIntervalId !== undefined) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'VPN watchdog started');
    VpnService.watchdogIntervalId = setInterval(() => {
      VpnService.checkAndRecover();
    }, WATCHDOG_INTERVAL_MS);
  }

  private static stopWatchdog(): void {
    if (VpnService.watchdogIntervalId !== undefined) {
      clearInterval(VpnService.watchdogIntervalId);
      VpnService.watchdogIntervalId = undefined;
    }
    VpnService.watchdogChecking = false;
    VpnService.restartInFlight = false;
    VpnService.consecutiveFailures = 0;
    hilog.info(DOMAIN, TAG, 'VPN watchdog stopped');
  }

  private static async checkAndRecover(): Promise<void> {
    if (!VpnService.shouldRun || VpnService.watchdogChecking || VpnService.restartInFlight ||
      Date.now() < VpnService.watchdogGraceUntil) {
      return;
    }

    VpnService.watchdogChecking = true;
    try {
      const status: ControllerStatus = await MihomoControllerService.checkVersion();
      if (status.available) {
        VpnService.consecutiveFailures = 0;
        return;
      }

      VpnService.consecutiveFailures++;
      hilog.warn(
        DOMAIN,
        TAG,
        'VPN watchdog controller failure %{public}d/%{public}d: %{public}s',
        VpnService.consecutiveFailures,
        WATCHDOG_FAILURE_THRESHOLD,
        status.message
      );
      if (VpnService.consecutiveFailures < WATCHDOG_FAILURE_THRESHOLD) {
        return;
      }
    } catch (err) {
      VpnService.consecutiveFailures++;
      hilog.warn(
        DOMAIN,
        TAG,
        'VPN watchdog check exception %{public}d/%{public}d: %{public}s',
        VpnService.consecutiveFailures,
        WATCHDOG_FAILURE_THRESHOLD,
        JSON.stringify(err)
      );
      if (VpnService.consecutiveFailures < WATCHDOG_FAILURE_THRESHOLD) {
        return;
      }
    } finally {
      VpnService.watchdogChecking = false;
    }

    await VpnService.restartFromWatchdog();
  }

  private static async restartFromWatchdog(): Promise<void> {
    if (!VpnService.shouldRun || VpnService.restartInFlight || VpnService.configPath.length === 0) {
      return;
    }
    VpnService.restartInFlight = true;
    VpnService.consecutiveFailures = 0;
    try {
      hilog.warn(DOMAIN, TAG, 'VPN extension unavailable; requesting automatic restart');
      await vpnExtension.startVpnExtensionAbility(createVpnWant(VpnService.configPath));
      await VpnBackgroundTaskService.startIfVpnRunning();
      hilog.info(DOMAIN, TAG, 'VPN extension automatic restart requested successfully');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'VPN extension automatic restart failed: %{public}s', JSON.stringify(err));
    } finally {
      VpnService.watchdogGraceUntil = Date.now() + WATCHDOG_RESTART_COOLDOWN_MS;
      VpnService.restartInFlight = false;
    }
  }

  static async protectSocket(fd: number): Promise<boolean> {
    try {
      nativeCore.protectSocket(fd);
      return true;
    } catch (err) {
      return false;
    }
  }
}
