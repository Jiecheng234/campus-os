import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { getTurboModuleList } from '../turbomodules/TurboModuleRegistry';

const DOMAIN = 0xCAFE;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'CampusOS', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS EntryAbility onCreate');

    // TODO(Phase 4): Initialize React Native runtime
    // 1. Create RN instance: const rnInstance = await RNInstanceFactory.create(this.context);
    // 2. Register TurboModules: getTurboModuleList().forEach(m => rnInstance.registerTurboModule(m.name, () => m.factory(ctx)));
    // 3. Load JS bundle: rnInstance.loadBundle('assets://index.harmony.bundle');
    // 4. Create ReactRootView and set as content
    hilog.info(DOMAIN, 'CampusOS', 'TurboModules available: %{public}d', getTurboModuleList().length);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS EntryAbility onDestroy');
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

    // Currently loads native ArkUI page; will be replaced with RN ReactRootView
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code !== undefined && err.code !== 0) {
        hilog.error(DOMAIN, 'CampusOS', 'Failed to load content. code=%{public}d msg=%{public}s', err.code, err.message);
        return;
      }
      hilog.info(DOMAIN, 'CampusOS', 'Content loaded successfully.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'CampusOS', 'CampusOS onForeground');
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