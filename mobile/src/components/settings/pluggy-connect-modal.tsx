import { useEffect, useRef, useState, type ReactNode } from 'react';
import { ActivityIndicator, Linking, Modal, Pressable, StyleSheet, Text, useColorScheme, View } from 'react-native';
import { PluggyConnect } from 'react-native-pluggy-connect';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ActionButton, settingsStyles } from '@/components/settings/ui';
import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { language, t } from '@/lib/i18n';
import { connected, connectSession, usePluggy, type ConnectSession } from '@/lib/pluggy-store';

function Overlay({ children }: { children: ReactNode }) {
  const theme = useTheme();
  return <View style={[styles.overlay, { backgroundColor: theme.background }]}>{children}</View>;
}

/** Pluggy's Connect widget, full screen. With `updating`, it reconnects that item instead of adding one. */
export function PluggyConnectModal({
  updating,
  onClose,
  onRenew,
}: {
  updating: string | null;
  onClose: () => void;
  onRenew: (id: string) => void;
}) {
  const theme = useTheme();
  const scheme = useColorScheme();
  const { itemIDs } = usePluggy();
  const [session, setSession] = useState<ConnectSession | null>(null);
  const [fatalError, setFatalError] = useState<string | null>(null);
  const [lastError, setLastError] = useState<string | null>(null);
  const [isFinishing, setIsFinishing] = useState(false);
  const [isAlreadyConnected, setIsAlreadyConnected] = useState(false);
  // PluggyConnect keeps the callbacks from its first render, so they can't read state.
  const hasSucceeded = useRef(false);

  useEffect(() => {
    let isCurrent = true;
    connectSession(updating).then(
      (started) => {
        if (isCurrent) setSession(started);
      },
      (error: unknown) => {
        if (isCurrent) {
          const message = error instanceof Error ? error.message : String(error);
          setFatalError(t("Couldn't start Pluggy Connect: {message}", { message }));
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [updating]);

  const existing = itemIDs[0];

  return (
    <Modal animationType="slide" onRequestClose={onClose}>
      <SafeAreaView style={[styles.root, { backgroundColor: theme.background }]}>
        <View style={[styles.header, { borderBottomColor: theme.selected }]}>
          <Text numberOfLines={1} style={[styles.headerTitle, { color: theme.text }]}>
            {updating === null ? t('Connect account') : t('Renew connection')}
          </Text>
          <Pressable accessibilityRole="button" hitSlop={8} onPress={onClose} style={styles.headerAction}>
            <Text style={[settingsStyles.label, { color: theme.link }]}>{t('Cancel')}</Text>
          </Pressable>
        </View>
        {lastError && (
          <Text style={[settingsStyles.caption, styles.lastError, { color: theme.textSecondary }]}>{lastError}</Text>
        )}
        <View style={styles.root}>
          {session && (
            <PluggyConnect
              connectToken={session.token}
              connectorIds={updating === null && session.connectorId !== null ? [session.connectorId] : undefined}
              // Keeps the bank's sign-in in the app, so its result comes straight back to the widget. The default
              // sends it to the system browser, which then has no way back here.
              forceOauthInBrowser={false}
              includeSandbox={false}
              language={language}
              onClose={() => {
                if (!hasSucceeded.current) onClose();
              }}
              onError={(error) => {
                if (error.message === 'ITEM_USER_ALREADY_EXISTS' && updating === null) {
                  setIsAlreadyConnected(true);
                } else {
                  setLastError(error.message);
                }
              }}
              onSuccess={({ item }) => {
                hasSucceeded.current = true;
                setIsFinishing(true);
                void connected(item.id, updating).then(onClose);
              }}
              theme={scheme === 'dark' ? 'dark' : 'light'}
              updateItem={updating ?? undefined}
            />
          )}
          {(!session || isFinishing) && !fatalError && (
            <Overlay>
              <ActivityIndicator color={theme.textSecondary} />
              <Text style={[settingsStyles.label, styles.centered, { color: theme.textSecondary }]}>
                {isFinishing ? t('Syncing your accounts…') : t('Opening Pluggy Connect…')}
              </Text>
            </Overlay>
          )}
          {fatalError && (
            <Overlay>
              <Text style={[settingsStyles.label, styles.centered, { color: theme.text }]}>{fatalError}</Text>
              <ActionButton title={t('Close')} onPress={onClose} />
            </Overlay>
          )}
          {isAlreadyConnected && (
            <Overlay>
              <Text style={[styles.noticeTitle, styles.centered, { color: theme.text }]}>
                {t('This Meu Pluggy account is already connected')}
              </Text>
              <Text style={[settingsStyles.label, styles.centered, { color: theme.textSecondary }]}>
                {t("One MeuPluggy connection covers every bank and broker you authorize in Meu Pluggy. To add another institution, authorize it at meu.pluggy.ai; it shows up on Cymba's next sync.")}
              </Text>
              <ActionButton title={t('Open Meu Pluggy')} onPress={() => void Linking.openURL('https://meu.pluggy.ai')} />
              {existing && (
                <ActionButton title={t('Renew existing connection')} isPrimary onPress={() => onRenew(existing)} />
              )}
              <ActionButton title={t('Close')} onPress={onClose} />
            </Overlay>
          )}
        </View>
      </SafeAreaView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: Spacing.three,
    paddingHorizontal: Spacing.three,
    minHeight: 52,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerTitle: {
    flex: 1,
    fontSize: 17,
    fontWeight: '600',
  },
  headerAction: {
    minHeight: 44,
    justifyContent: 'center',
  },
  lastError: {
    paddingHorizontal: Spacing.three,
    paddingVertical: Spacing.two,
  },
  overlay: {
    ...StyleSheet.absoluteFill,
    alignItems: 'stretch',
    justifyContent: 'center',
    gap: Spacing.three,
    padding: Spacing.four,
  },
  noticeTitle: {
    fontSize: 18,
    fontWeight: '600',
  },
  centered: {
    textAlign: 'center',
  },
});
