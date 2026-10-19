import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { getTurboModuleList } from '../turbomodules/TurboModuleRegistry';
import { runPhase4SelfTest } from '../utils/Phase4SelfTest';
import { PreferencesStorage } from '../storage/PreferencesStorage';
import { SettingsManager } from '../state/SettingsManager';
import { I18n } from '../utils/I18n';
import { AlipayPaymentService } from '../services/payment/AlipayPaymentService';
import { runPaymentSelfTest } from '../services/payment/PaymentSelfTest';

const DOMAIN = 0xCAFE;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'CampusOS', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS EntryAbility onCreate');
    PreferencesStorage.init(this.context);
    // 尽早开始加载持久化设置（幂等；onWindowStageCreate 复用同一任务）
    SettingsManager.ensureLoaded();

    // TODO(Phase 4): Initialize React Native runtime
    // 1. Create RN instance: const rnInstance = await RNInstanceFactory.create(this.context);
    // 2. Register TurboModules: getTurboModuleList().forEach(m => rnInstance.registerTurboModule(m.name, () => m.factory(ctx)));
    // 3. Load JS bundle: rnInstance.loadBundle('assets://index.harmony.bundle');
    // 4. Create ReactRootView and set as content
    hilog.info(DOMAIN, 'CampusOS', 'TurboModules available: %{public}d', getTurboModuleList().length);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS EntryAbility onDestroy');
    // 退出钩子：取消信任（"待清除"标记为真）→ 清除已持久化凭证并复位标记。
    // 异步清除可能未及完成即进程结束——强杀场景由启动兜底（下方 purgeCredentialsIfUntrusted）覆盖。
    SettingsManager.purgeCredentialsIfPendingClear().catch((): void => {
      hilog.error(DOMAIN, 'CampusOS', 'TRUST exit purge failed');
    });
    // TODO(Phase 4): Destroy RN instance
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS onWindowStageCreate');

    // Use ArkUI expandSafeArea to replace react-native-safe-area-context
    windowStage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setWindowLayoutFullScreen(true);

      const cutoutArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const cutoutBottom: number = cutoutArea.topRect.height > 0 ?
        cutoutArea.topRect.top + cutoutArea.topRect.height : 0;
      AppStorage.setOrCreate<number>('cutoutBottom', cutoutBottom);
      hilog.info(DOMAIN, 'CampusOS', 'Cutout bottom: %{public}d px', cutoutBottom);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'CampusOS', 'setWindowLayoutFullScreen failed: %{public}s', err.message);
      AppStorage.setOrCreate<number>('cutoutBottom', 0);
    });

    // 设置加载完成后才装载首页：保证偏好（演示模式/信任设备/语言）重启后保持，
    // 且 AppStorage('locale') 在任何页面的 @StorageLink 绑定前就绪。
    // 启动兜底（信任策略）：装载首页前，若"未信任"或"待清除" → 清除可能残留的
    // 已持久化凭证并复位标记——覆盖强杀/异常退出时退出钩子未执行的场景，
    // 同时保证 Index.tryAutoLogin 不会读到应被清除的残留凭证。
    SettingsManager.ensureLoaded().then((): Promise<void> => {
      return SettingsManager.purgeCredentialsIfUntrusted();
    }).then((): void => {
      I18n.init();
      // Currently loads native ArkUI page; will be replaced with RN ReactRootView
      windowStage.loadContent('pages/Index', (err: BusinessError) => {
        if (err.code !== undefined && err.code !== 0) {
          hilog.error(DOMAIN, 'CampusOS', 'Failed to load content. code=%{public}d msg=%{public}s', err.code, err.message);
          return;
        }
        hilog.info(DOMAIN, 'CampusOS', 'Content loaded successfully.');
        runPhase4SelfTest();
        runPaymentSelfTest().then((paymentFailures: number): void => {
          hilog.info(DOMAIN, 'CampusOS', 'Payment self-test failures: %{public}d', paymentFailures);
        }).catch((error: BusinessError): void => {
          hilog.error(DOMAIN, 'CampusOS', 'Payment self-test failed to run code=%{public}d', error.code);
        });
      });
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS onForeground');
    // 从支付宝返回时投递一次性支付回读事件；无 pending 时为零次。
    AlipayPaymentService.notifyForeground();
    // TODO(Phase 6): Trigger workflow checks on foreground (migrate from AppState listener)
    // Equivalent to: AppState.addEventListener('change', 'active') => runWorkflowChecks()
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS onBackground');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS onNewWant');
  }
}