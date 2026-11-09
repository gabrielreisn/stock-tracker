import { SymbolView } from 'expo-symbols';
import { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { PluggyConnectModal } from '@/components/settings/pluggy-connect-modal';
import { ActionButton, LinkedText, settingsStyles, SettingsGroup } from '@/components/settings/ui';
import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { formatTime, t } from '@/lib/i18n';
import {
  forgetCredentials,
  institutionsOf,
  isConfigured,
  needsReconnect,
  removeItem,
  saveSecret,
  setClientId,
  sync,
  syncIfNeeded,
  usePluggy,
  type PluggyState,
} from '@/lib/pluggy-store';

/** Keeps the keyboard and the system's password manager from second-guessing pasted credentials. */
const credentialInputProps = {
  autoCapitalize: 'none',
  autoComplete: 'off',
  autoCorrect: false,
  importantForAutofill: 'no',
  spellCheck: false,
  textContentType: 'none',
} as const;

function confirmRemove(id: string) {
  Alert.alert(t('Remove this connection?'), t('It stays in Pluggy, but Cymba stops syncing it.'), [
    { text: t('Cancel'), style: 'cancel' },
    { text: t('Remove'), style: 'destructive', onPress: () => removeItem(id) },
  ]);
}

function confirmForget() {
  Alert.alert(t('Forget the client secret?'), t('You will need to paste it again to sync.'), [
    { text: t('Cancel'), style: 'cancel' },
    { text: t('Forget'), style: 'destructive', onPress: () => void forgetCredentials() },
  ]);
}

function Guide() {
  const theme = useTheme();
  const stepStyle = [settingsStyles.caption, { color: theme.textSecondary }];

  return (
    <View style={settingsStyles.row}>
      <Text style={[settingsStyles.label, styles.guideTitle, { color: theme.text }]}>{t('Set up once')}</Text>
      <LinkedText
        style={stepStyle}
        text={t('1. Create a free account at [meu.pluggy.ai](https://meu.pluggy.ai) and connect your banks and brokers there.')}
      />
      <LinkedText
        style={stepStyle}
        text={t('2. In the [Pluggy dashboard](https://dashboard.pluggy.ai), open your application and copy its Client ID and Client Secret.')}
      />
      <Text style={stepStyle}>
        {t('3. Paste them below and tap Connect a bank or broker. Each connection shares one institution from Meu Pluggy; connect again for the next one.')}
      </Text>
    </View>
  );
}

function ClientIdRow({ state }: { state: PluggyState }) {
  const theme = useTheme();

  return (
    <View style={settingsStyles.row}>
      <Text style={[settingsStyles.label, { color: theme.text }]}>{t('Client ID')}</Text>
      <TextInput
        {...credentialInputProps}
        accessibilityLabel={t('Client ID')}
        editable={!state.hasSecret}
        onChangeText={setClientId}
        placeholder={t('From your Pluggy application')}
        placeholderTextColor={theme.textSecondary}
        style={[
          styles.input,
          { backgroundColor: theme.selected, color: state.hasSecret ? theme.textSecondary : theme.text },
        ]}
        value={state.clientId}
      />
    </View>
  );
}

function ClientSecretRow({ state }: { state: PluggyState }) {
  const theme = useTheme();
  const [secret, setSecret] = useState('');

  if (state.hasSecret) {
    return (
      <View style={[settingsStyles.row, styles.savedSecret]}>
        <View style={styles.text}>
          <Text style={[settingsStyles.label, { color: theme.text }]}>{t('Client secret')}</Text>
          <Text style={[settingsStyles.caption, { color: theme.textSecondary }]}>{t('Saved on this device')}</Text>
        </View>
        <ActionButton title={t('Forget')} onPress={confirmForget} />
      </View>
    );
  }

  return (
    <View style={settingsStyles.row}>
      <Text style={[settingsStyles.label, { color: theme.text }]}>{t('Client secret')}</Text>
      <TextInput
        {...credentialInputProps}
        accessibilityLabel={t('Client secret')}
        onChangeText={setSecret}
        secureTextEntry
        style={[styles.input, { backgroundColor: theme.selected, color: theme.text }]}
        value={secret}
      />
      <ActionButton
        title={t('Save')}
        isDisabled={state.clientId === '' || secret.trim() === ''}
        onPress={() => {
          void saveSecret(secret).then((isSaved) => {
            if (isSaved) setSecret('');
          });
        }}
      />
    </View>
  );
}

function ConnectionRow({
  id,
  state,
  onRenew,
}: {
  id: string;
  state: PluggyState;
  onRenew: () => void;
}) {
  const theme = useTheme();
  const item = state.items.find((candidate) => candidate.id === id);
  const reconnect = needsReconnect(state, id);
  const statusColor = reconnect ? theme.warning : item?.status === 'UPDATED' ? theme.success : theme.textSecondary;
  const name = institutionsOf(state, id) ?? item?.connector?.name ?? t('Connection');

  return (
    <View style={[settingsStyles.row, styles.connection]}>
      <View style={[styles.status, { backgroundColor: statusColor }]} />
      <View style={styles.text}>
        <Text style={[settingsStyles.label, { color: theme.text }]}>{name}</Text>
        <Text
          ellipsizeMode="middle"
          numberOfLines={1}
          style={[settingsStyles.caption, { color: reconnect ? theme.warning : theme.textSecondary }]}>
          {reconnect ? (item?.error?.message ?? t('Needs to be reconnected')) : id}
        </Text>
      </View>
      <Pressable accessibilityRole="button" hitSlop={8} onPress={onRenew} style={styles.iconButton}>
        <Text style={[settingsStyles.label, { color: reconnect ? theme.warning : theme.link }]}>
          {reconnect ? t('Reconnect') : t('Renew')}
        </Text>
      </Pressable>
      <Pressable
        accessibilityLabel={t('Remove')}
        accessibilityRole="button"
        hitSlop={8}
        onPress={() => confirmRemove(id)}
        style={styles.iconButton}>
        <SymbolView
          name={{ ios: 'minus.circle', android: 'do_not_disturb_on' }}
          size={22}
          tintColor={theme.textSecondary}
        />
      </Pressable>
    </View>
  );
}

function SyncStatus({ state }: { state: PluggyState }) {
  const theme = useTheme();
  if (state.error) {
    return <Text style={[settingsStyles.caption, { color: theme.warning }]}>{state.error}</Text>;
  }
  if (!state.lastSync) return null;
  return (
    <Text style={[settingsStyles.caption, { color: theme.textSecondary }]}>
      {t('Synced {count} investments at {time}', {
        count: state.investments.length,
        time: formatTime(state.lastSync),
      })}
    </Text>
  );
}

export function OpenFinanceSection({ inOnboarding = false }: { inOnboarding?: boolean }) {
  const theme = useTheme();
  const state = usePluggy();
  const [connecting, setConnecting] = useState<{ updating: string | null } | null>(null);
  const configured = isConfigured(state);

  useEffect(function refreshOpenFinanceWhenOpened() { void syncIfNeeded(); }, []);

  return (
    <>
      <SettingsGroup
        title={t('Open Finance')}
        footer={t('Your client secret stays in secure storage on this device and only leaves it to sign in to Pluggy. Meu Pluggy consent lasts a year; when it lapses, use Reconnect.')}>
        {!configured && !inOnboarding && <Guide />}
        <ClientIdRow state={state} />
        <ClientSecretRow state={state} />
        {state.itemIDs.map((id) => (
          <ConnectionRow key={id} id={id} state={state} onRenew={() => setConnecting({ updating: id })} />
        ))}
        <View style={settingsStyles.row}>
          <ActionButton
            title={state.itemIDs.length === 0 ? t('Connect a bank or broker') : t('Connect another bank or broker')}
            isPrimary
            isDisabled={!configured}
            onPress={() => setConnecting({ updating: null })}
          />
          <ActionButton
            title={t('Sync now')}
            isDisabled={!configured || state.itemIDs.length === 0 || state.isSyncing}
            onPress={() => void sync()}
          />
          {state.isSyncing && <ActivityIndicator color={theme.textSecondary} />}
          <SyncStatus state={state} />
        </View>
      </SettingsGroup>
      {connecting && (
        <PluggyConnectModal
          key={connecting.updating ?? 'new'}
          updating={connecting.updating}
          onClose={() => setConnecting(null)}
          onRenew={(id) => setConnecting({ updating: id })}
        />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  guideTitle: {
    fontWeight: '600',
  },
  input: {
    minHeight: 44,
    borderRadius: 10,
    paddingHorizontal: 12,
    fontSize: 15,
  },
  savedSecret: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.three,
  },
  connection: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  status: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  text: {
    flex: 1,
    gap: 2,
  },
  iconButton: {
    minHeight: 44,
    minWidth: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
