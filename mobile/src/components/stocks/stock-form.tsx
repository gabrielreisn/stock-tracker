import { useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { Card, Label, Title } from '@/components/bonds/ui';
import { ActionButton } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import { saveStock } from '@/lib/stock-store';
import { t } from '@/lib/i18n';
import { fetchStockQuote } from '@/lib/stock-market';
import { stockNumber } from '@/lib/stocks';
import type { StockHolding } from '@/types/stocks';

export function StockForm({ holding, onClose, onSaved }: { holding?: StockHolding; onClose: () => void; onSaved: () => void }) {
  const theme = useTheme();
  const [ticker, setTicker] = useState(holding?.ticker ?? '');
  const [quantity, setQuantity] = useState(holding ? String(holding.quantity).replace('.', ',') : '');
  const [price, setPrice] = useState(holding?.averagePrice ? String(holding.averagePrice).replace('.', ',') : '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);
  const symbol = ticker.trim().toUpperCase().replace(/\.SA$/, '');
  const shares = stockNumber(quantity), paid = stockNumber(price);
  const valid = /^[A-Z][A-Z0-9.-]{0,14}$/.test(symbol) && shares !== undefined && (!price.trim() || paid !== undefined);
  async function save() {
    if (!valid || busy || shares === undefined) return;
    setBusy(true); setError(false);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      if (!holding) await fetchStockQuote(symbol, controller.signal);
      saveStock(symbol, shares, paid, !!holding);
      onSaved();
    } catch { setError(true); }
    clearTimeout(timeout); setBusy(false);
  }
  const inputStyle = [styles.input, { color: theme.text, backgroundColor: theme.background }];
  return <Card><Title>{t(holding ? 'Edit stock' : 'Add stock')}</Title>
    <Label>{t('Ticker')}</Label><TextInput accessibilityLabel={t('Ticker')} value={ticker} onChangeText={setTicker} editable={!holding && !busy} autoCapitalize="characters" autoCorrect={false} placeholder="PETR4 / AAPL" placeholderTextColor={theme.textSecondary} style={inputStyle} />
    <Label>{t('Shares')}</Label><TextInput accessibilityLabel={t('Shares')} value={quantity} onChangeText={setQuantity} keyboardType="decimal-pad" editable={!busy} style={inputStyle} />
    <Label>{t('Average price')}</Label><TextInput accessibilityLabel={t('Average price')} value={price} onChangeText={setPrice} keyboardType="decimal-pad" editable={!busy} placeholder={t('Optional')} placeholderTextColor={theme.textSecondary} style={inputStyle} />
    <Label secondary>{t('Use the stock currency: BRL for B3, USD for US. Leave average price empty to clear it.')}</Label>
    {error && <Label>{t('Could not validate this ticker. Check the symbol and connection, then retry.')}</Label>}
    <View style={styles.actions}><ActionButton title={t('Cancel')} onPress={onClose} isDisabled={busy} /><ActionButton title={t(busy ? 'Checking…' : 'Save')} onPress={() => void save()} isPrimary isDisabled={!valid || busy} /></View>
  </Card>;
}
const styles = StyleSheet.create({ input: { minHeight: 48, borderRadius: 10, paddingHorizontal: 12, fontSize: 16 }, actions: { flexDirection: 'row', gap: 12 } });
