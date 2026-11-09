import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import { styles } from '@/components/funds/styles';
import { ActionButton } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import {
  dayInput,
  deleteFund,
  demoFunds,
  formatCNPJ,
  fundPurpose,
  parseDay,
  parseDecimal,
  purposeLabels,
  purposes,
  saveFund,
} from '@/lib/funds';
import { t, type StringKey } from '@/lib/i18n';
import type { FundHolding, FundHoldingKind, FundPurpose } from '@/types';

export default function FundEditorScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { holdings } = demoFunds.useValue();
  const holding = holdings.find((fund) => fund.id === id);
  if (id !== 'new' && !holding) return <MissingFund />;
  return <FundEditor key={id} holding={holding} />;
}
function MissingFund() {
  const theme = useTheme();
  return (
    <View style={[styles.content, { backgroundColor: theme.background }]}>
      <Text style={{ color: theme.text }}>{t('Fund not found.')}</Text>
    </View>
  );
}
function FundEditor({ holding }: { holding?: FundHolding }) {
  const theme = useTheme();
  const {
    cnpj,
    setCnpj,
    name,
    setName,
    kind,
    setKind,
    quantity,
    setQuantity,
    purpose,
    setPurpose,
    taxExempt,
    setTaxExempt,
    price,
    setPrice,
    date,
    setDate,
  } = useFundDraft(holding);
  const digits = cnpj.replace(/\D/g, '');
  const parsedQuantity = parseDecimal(quantity);
  const parsedPrice = price.trim() ? parseDecimal(price) : undefined;
  const parsedDate = parseDay(date);
  const duplicate = demoFunds
    .get()
    .holdings.some((fund) => fund.cnpj === digits && fund.id !== holding?.id);
  const valid =
    digits.length === 14 &&
    !!name.trim() &&
    parsedQuantity !== undefined &&
    !duplicate &&
    (!price.trim() ||
      (parsedPrice !== undefined && parsedDate !== undefined)) &&
    Number.isFinite((parsedPrice ?? 1) * (parsedQuantity ?? 0));
  const fields: {
    label: StringKey;
    value: string;
    change: (value: string) => void;
    numeric?: boolean;
    placeholder?: string;
  }[] = [
    {
      label: 'CNPJ',
      value: cnpj,
      change: setCnpj,
      placeholder: '00.000.000/0000-00',
    },
    { label: 'Name', value: name, change: setName },
    { label: 'Shares', value: quantity, change: setQuantity, numeric: true },
  ];
  const renderedFields = fields.map((field) => (
    <Field key={field.label} {...field} />
  ));
  const kinds = (['fif', 'fidc', 'fip'] as const).map((value) => (
    <ActionButton
      key={value}
      title={value.toUpperCase()}
      isPrimary={kind === value}
      onPress={() => setKind(value)}
    />
  ));
  const purposeButtons = purposes.map((value) => (
    <ActionButton
      key={value}
      title={t(purposeLabels[value])}
      isPrimary={purpose === value}
      onPress={() => setPurpose(value)}
    />
  ));
  const inferred = fundPurpose({
    id: '',
    cnpj: digits,
    name,
    kind,
    quantity: 0,
    taxExempt,
  });
  function save() {
    if (!valid || parsedQuantity === undefined) return;
    const statementChanged =
      parsedPrice !== holding?.statementPrice ||
      (parsedPrice ? parsedDate : undefined) !== holding?.statementDay;
    saveFund({
      id:
        holding?.id ??
        `demo-fund-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      cnpj: digits,
      name: name.trim(),
      kind,
      quantity: parsedQuantity,
      taxExempt,
      purpose,
      statementPrice: parsedPrice,
      statementDay: parsedPrice ? parsedDate : undefined,
      statementFromOpenFinance: statementChanged
        ? undefined
        : holding?.statementFromOpenFinance,
    });
    router.back();
  }
  function confirmDelete() {
    Alert.alert(t('Delete this fund?'), holding?.name, [
      { text: t('Cancel'), style: 'cancel' },
      {
        text: t('Delete'),
        style: 'destructive',
        onPress: () => {
          if (holding) deleteFund(holding.id);
          router.back();
        },
      },
    ]);
  }
  return (
    <KeyboardAvoidingView
      style={[styles.root, { backgroundColor: theme.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      keyboardVerticalOffset={100}
    >
      <ScrollView
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={styles.content}
      >
        <Text
          accessibilityRole="header"
          style={[styles.title, { color: theme.text }]}
        >
          {t(holding ? 'Edit fund' : 'Add fund')}
        </Text>
        <Text style={[styles.caption, { color: theme.textSecondary }]}>
          {t('Demo account · Changes last for this session.')}
        </Text>
        {renderedFields}
        {duplicate && (
          <Text accessibilityRole="alert" style={{ color: theme.warning }}>
            {t('A fund with this CNPJ already exists.')}
          </Text>
        )}
        <Text style={{ color: theme.text }}>{t('Type')}</Text>
        <View style={styles.wrap}>{kinds}</View>
        <View style={styles.row}>
          <Text style={{ color: theme.text }}>{t('Tax exempt')}</Text>
          <Switch
            accessibilityLabel={t('Tax exempt')}
            value={taxExempt}
            onValueChange={setTaxExempt}
          />
        </View>
        <Text style={{ color: theme.text }}>{t('Purpose')}</Text>
        <View style={styles.wrap}>
          <ActionButton
            title={`${t('Automatic')} (${t(purposeLabels[inferred])})`}
            isPrimary={purpose === undefined}
            onPress={() => setPurpose(undefined)}
          />
          {purposeButtons}
        </View>
        <View style={[styles.card, { backgroundColor: theme.surface }]}>
          <Text style={[styles.name, { color: theme.text }]}>
            {t('Statement price (optional)')}
          </Text>
          <Field label="Share price" value={price} change={setPrice} numeric />
          <Field
            label="Price date"
            value={date}
            change={setDate}
            placeholder="YYYY-MM-DD"
          />
          <Text style={[styles.caption, { color: theme.textSecondary }]}>
            {t(
              'Use a positive price and a valid date (YYYY-MM-DD), no later than today. Clear the price to remove the valuation.',
            )}
          </Text>
        </View>
        <Text style={[styles.caption, { color: theme.textSecondary }]}>
          {t(
            'Enter a 14-digit CNPJ, a name and a positive number of shares. Decimal comma or point accepted; omit thousands separators.',
          )}
        </Text>
        <ActionButton
          title={t('Save')}
          isPrimary
          isDisabled={!valid}
          onPress={save}
        />
        <ActionButton title={t('Cancel')} onPress={() => router.back()} />
        {holding && (
          <ActionButton title={t('Delete')} onPress={confirmDelete} />
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
function Field({
  label,
  value,
  change,
  numeric,
  placeholder,
}: {
  label: StringKey;
  value: string;
  change: (value: string) => void;
  numeric?: boolean;
  placeholder?: string;
}) {
  const theme = useTheme();
  return (
    <View style={{ gap: 8 }}>
      <Text style={{ color: theme.text }}>{t(label)}</Text>
      <TextInput
        accessibilityLabel={t(label)}
        value={value}
        onChangeText={change}
        keyboardType={numeric ? 'decimal-pad' : 'default'}
        autoCorrect={false}
        placeholder={placeholder}
        placeholderTextColor={theme.textSecondary}
        style={[
          styles.input,
          { color: theme.text, borderColor: theme.selected },
        ]}
      />
    </View>
  );
}

function useFundDraft(holding?: FundHolding) {
  const [cnpj, setCnpj] = useState(holding ? formatCNPJ(holding.cnpj) : '');
  const [name, setName] = useState(holding?.name ?? '');
  const [kind, setKind] = useState<FundHoldingKind>(holding?.kind ?? 'fif');
  const [quantity, setQuantity] = useState(
    holding ? String(holding.quantity) : '',
  );
  const [purpose, setPurpose] = useState<FundPurpose | undefined>(
    holding?.purpose,
  );
  const [taxExempt, setTaxExempt] = useState(holding?.taxExempt ?? false);
  const [price, setPrice] = useState(
    () => holding?.statementPrice?.toString() ?? '',
  );
  const [date, setDate] = useState(() => dayInput(holding?.statementDay));
  return {
    cnpj,
    setCnpj,
    name,
    setName,
    kind,
    setKind,
    quantity,
    setQuantity,
    purpose,
    setPurpose,
    taxExempt,
    setTaxExempt,
    price,
    setPrice,
    date,
    setDate,
  };
}
