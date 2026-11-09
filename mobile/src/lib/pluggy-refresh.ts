import { isRunningInExpoGo, requireOptionalNativeModule } from 'expo';
import { AppState } from 'react-native';
import { isConfigured, prepareBackgroundCredentials, syncIfNeeded, usePluggy } from '@/lib/pluggy-store';
import { useEffect } from 'react';

const TASK = 'cymba-open-finance-sync';
const nativeAvailable = !isRunningInExpoGo() && !!requireOptionalNativeModule('ExpoBackgroundTask')
  && !!requireOptionalNativeModule('ExpoTaskManager');
export const backgroundSyncAvailable = nativeAvailable;

// Require only when present: Expo Go and older native builds still run foreground refresh safely.
// Both packages unconditionally require their native module at import time.
// eslint-disable-next-line @typescript-eslint/no-require-imports -- Defer native imports until availability is confirmed.
const taskManager: typeof import('expo-task-manager') | null = nativeAvailable ? require('expo-task-manager') : null;
// eslint-disable-next-line @typescript-eslint/no-require-imports -- Defer native imports until availability is confirmed.
const background: typeof import('expo-background-task') | null = nativeAvailable ? require('expo-background-task') : null;
if (taskManager && background && !taskManager.isTaskDefined(TASK)) {
  taskManager.defineTask(TASK, async function refreshOpenFinanceInBackground() {
    const success = await syncIfNeeded();
    return success ? background!.BackgroundTaskResult.Success : background!.BackgroundTaskResult.Failed;
  });
}

async function configureBackground(enabled: boolean) {
  if (!taskManager || !background) return;
  try {
    const registered = await taskManager.isTaskRegisteredAsync(TASK);
    if (!enabled) {
      if (registered) await background.unregisterTaskAsync(TASK);
      return;
    }
    if (await background.getStatusAsync() !== background.BackgroundTaskStatus.Available) return;
    await prepareBackgroundCredentials();
    if (!registered) await background.registerTaskAsync(TASK, { minimumInterval: 360 });
  } catch {
    // A restricted OS, simulator or old native build still gets the foreground freshness check.
  }
}

export function useOpenFinanceRefresh() {
  const state = usePluggy();
  const enabled = isConfigured(state) && state.itemIDs.length > 0;
  useEffect(function scheduleOpenFinanceRefresh() {
    // Serial calls avoid register/unregister racing when credentials change during startup.
    backgroundConfiguration = backgroundConfiguration.then(() => configureBackground(enabled));
    function refreshIfActive() {
      if (enabled && AppState.currentState === 'active') void syncIfNeeded();
    }
    refreshIfActive();
    const subscription = AppState.addEventListener('change', refreshIfActive);
    const timer = setInterval(refreshIfActive, 60_000);
    return () => { subscription.remove(); clearInterval(timer); };
  }, [enabled]);
}
let backgroundConfiguration = Promise.resolve();
