import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export interface ProxyFilterConfig {
  excludeText: string;
  hideTimeout: boolean;
  quickExcludes: string[];
}

export function createDefaultFilterConfig(): ProxyFilterConfig {
  return {
    excludeText: '',
    hideTimeout: false,
    quickExcludes: []
  };
}

const STORE_NAME: string = 'clash_harmony_preferences';
const KEY_FILTER_CONFIG: string = 'proxy_filter_config';

export class ProxyFilterService {
  private static cachedRawKey: string = '';
  private static cachedKeywords: string[] = [];

  static async loadConfig(context: common.Context): Promise<ProxyFilterConfig> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(KEY_FILTER_CONFIG, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        return createDefaultFilterConfig();
      }
      return ProxyFilterService.parse(raw);
    } catch (err) {
      return createDefaultFilterConfig();
    }
  }

  static async saveConfig(context: common.Context, config: ProxyFilterConfig): Promise<boolean> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.put(KEY_FILTER_CONFIG, JSON.stringify(config));
      await store.flush();
      return true;
    } catch (err) {
      return false;
    }
  }

  static parse(raw: string): ProxyFilterConfig {
    try {
      const obj = JSON.parse(raw) as Record<string, Object>;
      const excludeText = typeof obj.excludeText === 'string' ? obj.excludeText : '';
      const hideTimeout = typeof obj.hideTimeout === 'boolean' ? (obj.hideTimeout as boolean) : false;
      const quickExcludes: string[] = [];
      if (Array.isArray(obj.quickExcludes)) {
        for (let i = 0; i < obj.quickExcludes.length; i++) {
          if (typeof obj.quickExcludes[i] === 'string') {
            quickExcludes.push(obj.quickExcludes[i] as string);
          }
        }
      }
      return {
        excludeText: excludeText,
        hideTimeout: hideTimeout,
        quickExcludes: quickExcludes
      };
    } catch (err) {
      return createDefaultFilterConfig();
    }
  }

  static shouldExclude(name: string, meta: string, delay: string, status: string, config: ProxyFilterConfig, precomputedKeywords?: string[]): boolean {
    if (config.hideTimeout) {
      if (delay === 'timeout' || status === 'dead') {
        return true;
      }
    }

    const allKeywords: string[] = precomputedKeywords ? precomputedKeywords : ProxyFilterService.getNormalizedKeywords(config);
    if (allKeywords.length === 0) {
      return false;
    }

    const target: string = `${name} ${meta}`.toLowerCase();
    for (let i = 0; i < allKeywords.length; i++) {
      const kw: string = allKeywords[i];
      if (kw.length > 0 && target.indexOf(kw) >= 0) {
        return true;
      }
    }
    return false;
  }

  static getNormalizedKeywords(config: ProxyFilterConfig): string[] {
    const key: string = `${config.excludeText}:::${config.quickExcludes.join('|')}`;
    if (key === ProxyFilterService.cachedRawKey) {
      return ProxyFilterService.cachedKeywords;
    }

    const list: string[] = [];
    for (let i = 0; i < config.quickExcludes.length; i++) {
      const tag: string = config.quickExcludes[i].trim().toLowerCase();
      if (tag.length > 0 && list.indexOf(tag) < 0) {
        list.push(tag);
      }
    }

    if (config.excludeText.length > 0) {
      const tokens: string[] = config.excludeText.split(/[,，、;\s\n]+/);
      for (let i = 0; i < tokens.length; i++) {
        const token: string = tokens[i].trim().toLowerCase();
        if (token.length > 0 && list.indexOf(token) < 0) {
          list.push(token);
        }
      }
    }

    ProxyFilterService.cachedRawKey = key;
    ProxyFilterService.cachedKeywords = list;
    return list;
  }

  static countActiveFilters(config: ProxyFilterConfig): number {
    let count: number = config.quickExcludes.length;
    if (config.hideTimeout) {
      count++;
    }
    if (config.excludeText.length > 0) {
      const tokens: string[] = config.excludeText.split(/[,，、;\s\n]+/).filter((k: string) => k.trim().length > 0);
      count += tokens.length;
    }
    return count;
  }
}
