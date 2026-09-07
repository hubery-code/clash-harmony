import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { fileIo } from '@kit.CoreFileKit';
import { ClashProfile, createLocalProfile, createRemoteProfile, ProfileState } from '../models/Profile';
import { ClashConfigParserService, ParsedProxyNode } from './ClashConfigParserService';
import { ConvertedSubscription, GenericSubscriptionConverterService } from './GenericSubscriptionConverterService';
import { ProfileStore } from './ProfileStore';
import { SubscriptionService, SubscriptionUpdateResult } from './SubscriptionService';

export interface QrCodeScanImportResult {
  ok: boolean;
  message: string;
  state: ProfileState;
}

export class QrCodeScanImportService {
  static async scanAndImport(context: common.Context): Promise<QrCodeScanImportResult> {
    const state: ProfileState = await ProfileStore.load(context);
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: true
      };
      const scanResult: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
      if (!scanResult || !scanResult.originalValue) {
        return {
          ok: false,
          message: '未识别到二维码内容',
          state: state
        };
      }

      const rawText: string = scanResult.originalValue.trim();
      if (rawText.length === 0) {
        return {
          ok: false,
          message: '二维码内容为空',
          state: state
        };
      }

      return await QrCodeScanImportService.importScannedContent(context, rawText, state);
    } catch (err) {
      const errorStr: string = String(err);
      if (errorStr.indexOf('1000500002') >= 0 || errorStr.indexOf('cancel') >= 0 || errorStr.indexOf('canceled') >= 0) {
        return {
          ok: false,
          message: '已取消扫码',
          state: state
        };
      }
      return {
        ok: false,
        message: `扫码失败: ${err instanceof Error ? err.message : String(err)}`,
        state: state
      };
    }
  }

  static async importScannedContent(context: common.Context, content: string, currentState: ProfileState): Promise<QrCodeScanImportResult> {
    let text: string = content.trim();

    // 1. Clash scheme: clash://install-config?url=...
    if (text.startsWith('clash://install-config') || text.startsWith('clash://')) {
      const urlIndex = text.indexOf('url=');
      if (urlIndex >= 0) {
        let extracted = text.substring(urlIndex + 4);
        const ampIndex = extracted.indexOf('&');
        if (ampIndex >= 0) {
          extracted = extracted.substring(0, ampIndex);
        }
        try {
          text = decodeURIComponent(extracted);
        } catch (e) {
          text = extracted;
        }
      }
    }

    // 2. HTTP / HTTPS subscription link
    if (text.startsWith('http://') || text.startsWith('https://')) {
      const name: string = QrCodeScanImportService.createProfileNameFromUrl(text);
      const newProfile: ClashProfile = createRemoteProfile(name, text);
      const next: ProfileState = await ProfileStore.addRemote(context, newProfile);

      try {
        const updateResult: SubscriptionUpdateResult = await SubscriptionService.updateProfile(context, newProfile.uid);
        if (updateResult.ok) {
          return {
            ok: true,
            message: `扫码成功，已导入并更新订阅：${name}`,
            state: updateResult.state
          };
        }
      } catch (e) {
      }

      return {
        ok: true,
        message: `扫码成功，已添加订阅：${name}`,
        state: next
      };
    }

    // 3. Generic subscription / proxy node protocol links
    const converted: ConvertedSubscription = GenericSubscriptionConverterService.normalizeToClashYaml(text);
    if (converted.converted && converted.nodeCount > 0) {
      const uid: string = `scan_${Date.now()}`;
      const dir: string = `${context.filesDir}/profiles`;
      await QrCodeScanImportService.ensureDir(dir);
      const path: string = `${dir}/${uid}.yaml`;
      await QrCodeScanImportService.writeText(path, converted.text);
      const nodes: ParsedProxyNode[] = ClashConfigParserService.parseProxyNodes(converted.text);
      const profile: ClashProfile = createLocalProfile('扫码节点', path, nodes.length, QrCodeScanImportService.formatBytes(converted.text.length));
      const nextState: ProfileState = await ProfileStore.replace(context, profile);
      return {
        ok: true,
        message: `扫码成功，已导入 ${nodes.length} 个节点`,
        state: nextState
      };
    }

    // 4. Raw Clash YAML
    if (QrCodeScanImportService.looksLikeClashYaml(text)) {
      const uid: string = `scan_${Date.now()}`;
      const dir: string = `${context.filesDir}/profiles`;
      await QrCodeScanImportService.ensureDir(dir);
      const path: string = `${dir}/${uid}.yaml`;
      await QrCodeScanImportService.writeText(path, text);
      const nodes: ParsedProxyNode[] = ClashConfigParserService.parseProxyNodes(text);
      const profile: ClashProfile = createLocalProfile('扫码配置', path, nodes.length, QrCodeScanImportService.formatBytes(text.length));
      const nextState: ProfileState = await ProfileStore.replace(context, profile);
      return {
        ok: true,
        message: `扫码成功，已导入配置，解析 ${nodes.length} 个节点`,
        state: nextState
      };
    }

    return {
      ok: false,
      message: '二维码内容不是有效的订阅链接或节点配置',
      state: currentState
    };
  }

  private static looksLikeClashYaml(text: string): boolean {
    return text.indexOf('proxies:') >= 0 ||
      text.indexOf('proxy-providers:') >= 0 ||
      text.indexOf('proxy-groups:') >= 0 ||
      text.indexOf('rules:') >= 0;
  }

  private static async ensureDir(path: string): Promise<void> {
    try {
      await fileIo.mkdir(path, true);
    } catch (err) {
    }
  }

  private static async writeText(path: string, text: string): Promise<void> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, text);
    } finally {
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (err) {
        }
      }
    }
  }

  private static createProfileNameFromUrl(url: string): string {
    let value: string = url.replace('https://', '').replace('http://', '');
    const slashIndex: number = value.indexOf('/');
    if (slashIndex > 0) {
      value = value.substring(0, slashIndex);
    }
    return value.length > 0 ? value : '扫码订阅';
  }

  private static formatBytes(length: number): string {
    if (length < 1024) {
      return `${length} B`;
    }
    if (length < 1024 * 1024) {
      return `${Math.round(length / 1024)} KB`;
    }
    return `${(length / (1024 * 1024)).toFixed(1)} MB`;
  }
}
