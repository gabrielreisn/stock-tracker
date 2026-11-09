import { getLocales } from 'expo-localization';

// Same convention as macOS/Resources/pt-BR.lproj/Localizable.strings: the English text is the key.
const portuguese = {
  "Demo account": "Conta de demonstração",
  "Demo edits last for this session only.": "As alterações da demonstração duram apenas nesta sessão.",
  "Fixed rate": "Prefixado",
  "% of CDI": "% do CDI",
  "CDI + spread": "CDI + spread",
  "IPCA + spread": "IPCA + spread",
  "Invested": "Investido",
  "Gross value": "Valor bruto",
  "Income tax": "Imposto de renda",
  "IOF": "IOF",
  "Net value": "Valor líquido",
  "Gain": "Ganho",
  "Return": "Retorno",
  "Unit value": "Valor unitário",
  "At maturity (est., gross)": "No vencimento (est., bruto)",
  "Add bond": "Adicionar título",
  "Edit bond": "Editar título",
  "Delete": "Excluir",
  "Delete this bond?": "Excluir este título?",
  "Type": "Tipo",
  "Issuer": "Emissor",
  "Issuer CNPJ (optional)": "CNPJ do emissor (opcional)",
  "Code": "Código",
  "Issued (YYYY-MM-DD)": "Emissão (AAAA-MM-DD)",
  "Matures (YYYY-MM-DD)": "Vencimento (AAAA-MM-DD)",
  "Indexer": "Indexador",
  "Rate (% a year)": "Taxa (% ao ano)",
  "Spread (% a year)": "Spread (% ao ano)",
  "Quantity": "Quantidade",
  "Unit price at issue (R$)": "Preço unitário na emissão (R$)",
  "Enter an issuer, positive rate, quantity and price, valid dates from 2000–2070 with maturity after issue, and a 14-digit CNPJ if provided.": "Informe emissor, taxa, quantidade e preço positivos, datas válidas de 2000–2070 com vencimento após a emissão e CNPJ com 14 dígitos, se preenchido.",
  "Allocation by indexer": "Alocação por indexador",
  "Maturities": "Vencimentos",
  "Invested · valuations unavailable": "Investido · valores atualizados indisponíveis",
  "Net value today by maturity year": "Valor líquido hoje por ano de vencimento",
  "Issued": "Emissão",
  "Matures": "Vencimento",
  "Matured": "Vencido",
  "Rate": "Taxa",
  "Income tax + IOF": "IR + IOF",
  "FGC covered": "Coberto pelo FGC",
  "Not FGC covered": "Sem cobertura do FGC",
  "Valuation unavailable": "Valor atualizado indisponível",
  "Tax exempt": "Isento de IR",
  "Total net": "Total líquido",
  "Loading CDI and IPCA…": "Carregando CDI e IPCA…",
  "Rate history is unavailable. Fixed-rate bonds are still valued; other values are left blank.": "Histórico de taxas indisponível. Títulos prefixados continuam calculados; os demais valores ficam em branco.",
  "Retry": "Tentar novamente",
  "No bonds yet": "Nenhum título ainda",
  "Add CDBs, LCAs and other fixed income with their rate and dates.": "Adicione CDBs, LCAs e outros títulos de renda fixa com suas taxas e datas.",
  "Portfolio summary": "Resumo da carteira",
  "Holdings": "Títulos",
  "Ascending ↑": "Crescente ↑",
  "Descending ↓": "Decrescente ↓",
  "Values use business days over 252 with ANBIMA holidays, daily CDI compounding and monthly IPCA anniversaries. Income tax ranges from 22.5% to 15% on gains; exempt types pay no income tax. IOF applies within 30 days. Maturity projections carry forward the latest CDI or trailing 12-month IPCA and are estimates.": "Os valores usam dias úteis sobre 252 com feriados ANBIMA, CDI composto diariamente e IPCA nos aniversários mensais. O IR varia de 22,5% a 15% sobre os ganhos; tipos isentos não pagam IR. Há IOF nos primeiros 30 dias. Projeções de vencimento usam o último CDI ou IPCA acumulado em 12 meses e são estimativas.",

  '1. Create a free account at [meu.pluggy.ai](https://meu.pluggy.ai) and connect your banks and brokers there.':
    '1. Crie uma conta gratuita em [meu.pluggy.ai](https://meu.pluggy.ai) e conecte lá os seus bancos e corretoras.',
  '2. In the [Pluggy dashboard](https://dashboard.pluggy.ai), open your application and copy its Client ID and Client Secret.':
    '2. No [painel da Pluggy](https://dashboard.pluggy.ai), abra a sua aplicação e copie o Client ID e o Client Secret.',
  '3. Paste them below and tap Connect a bank or broker. Each connection shares one institution from Meu Pluggy; connect again for the next one.':
    '3. Cole-os abaixo e toque em Conectar banco ou corretora. Cada conexão compartilha uma instituição do Meu Pluggy; conecte de novo para a próxima.',
  'Add your Pluggy client ID and secret in Settings.': 'Adicione o client ID e o secret da Pluggy em Ajustes.',
  "B3's real-estate fund (FII) index, with distributions reinvested. Starts Dec 2010.":
    'Índice de fundos imobiliários (FII) da B3, com rendimentos reinvestidos. Começa em dez/2010.',
  Benchmarks: 'Indicadores',
  Bills: 'Contas',
  Bonds: 'Renda fixa',
  Cancel: 'Cancelar',
  'Categories & limits': 'Limites e categorias',
  'Client ID': 'Client ID',
  'Client secret': 'Client secret',
  Close: 'Fechar',
  'Coming soon': 'Em breve',
  'Connect a bank or broker': 'Conectar banco ou corretora',
  'Connect account': 'Conectar conta',
  'Connect another bank or broker': 'Conectar outro banco ou corretora',
  Connection: 'Conexão',
  "Couldn't save the secret on this device.": 'Não foi possível salvar o secret neste aparelho.',
  "Couldn't start Pluggy Connect: {message}": 'Não foi possível abrir o Pluggy Connect: {message}',
  Expenses: 'Compras e entradas',
  'FGC Watcher': 'Monitor do FGC',
  Finances: 'Finanças',
  Forget: 'Esquecer',
  'Forget the client secret?': 'Esquecer o client secret?',
  'From your Pluggy application': 'Da sua aplicação na Pluggy',
  'Fund Comparison': 'Comparar fundos',
  Funds: 'Fundos',
  "Ibovespa, B3's main stock index (a total-return index), via Yahoo (^BVSP).":
    'Ibovespa, o principal índice de ações da B3 (índice de retorno total), via Yahoo (^BVSP).',
  'Inflation plus a 6% real return a year — a typical long-term target.':
    'Inflação mais 6% de juro real ao ano, uma meta comum de longo prazo.',
  Insights: 'Insights',
  'Interbank deposit rate, the usual fixed-income yardstick. Banco Central, series 12.':
    'Taxa DI, a referência usual da renda fixa. Banco Central, série 12.',
  Investments: 'Investimentos',
  'It stays in Pluggy, but Cymba stops syncing it.': 'Ela continua na Pluggy, mas o Cymba para de sincronizá-la.',
  'Needs to be reconnected': 'Precisa ser reconectada',
  'Official inflation. IBGE, via Banco Central series 433.': 'Inflação oficial. IBGE, via Banco Central série 433.',
  "One MeuPluggy connection covers every bank and broker you authorize in Meu Pluggy. To add another institution, authorize it at meu.pluggy.ai; it shows up on Cymba's next sync.":
    'Uma conexão MeuPluggy cobre todos os bancos e corretoras que você autoriza no Meu Pluggy. Para adicionar outra instituição, autorize-a em meu.pluggy.ai; ela aparece na próxima sincronização do Cymba.',
  'Open Finance': 'Open Finance',
  'Open Meu Pluggy': 'Abrir o Meu Pluggy',
  'Opening Pluggy Connect…': 'Abrindo o Pluggy Connect…',
  Overview: 'Visão geral',
  'Pluggy returned {code}: {message}': 'A Pluggy retornou {code}: {message}',
  Reconnect: 'Reconectar',
  Remove: 'Remover',
  'Remove this connection?': 'Remover esta conexão?',
  Renew: 'Renovar',
  'Renew connection': 'Renovar conexão',
  'Renew existing connection': 'Renovar a conexão existente',
  'S&P 500 with dividends reinvested (^SP500TR), converted to reais at USD/BRL.':
    'S&P 500 com dividendos reinvestidos (^SP500TR), convertido para reais pelo dólar.',
  Save: 'Salvar',
  'Saved on this device': 'Salvo neste aparelho',
  'Set up once': 'Configure uma vez',
  Settings: 'Ajustes',
  Stocks: 'Ações',
  'Sync now': 'Sincronizar agora',
  'Synced {count} investments at {time}': '{count} investimentos sincronizados às {time}',
  'Syncing your accounts…': 'Sincronizando as suas contas…',
  'This Meu Pluggy account is already connected': 'Esta conta Meu Pluggy já está conectada',
  'Up to {max} at a time, so every line stays distinguishable. Rate-based ones are drawn dashed.':
    'Até {max} por vez, para que todas as linhas fiquem distinguíveis. Os baseados em taxa aparecem tracejados.',
  'You will need to paste it again to sync.': 'Será preciso colá-lo de novo para sincronizar.',
  'Your client secret stays in secure storage on this device and only leaves it to sign in to Pluggy. Meu Pluggy consent lasts a year; when it lapses, use Reconnect.':
    'O seu client secret fica guardado com segurança neste aparelho e só sai dele para entrar na Pluggy. O consentimento do Meu Pluggy dura um ano; quando vencer, use Reconectar.',
} as const;

export type StringKey = keyof typeof portuguese;

const locale = getLocales()[0];
const isPortuguese = locale?.languageCode === 'pt';

export const language = isPortuguese ? 'pt' : 'en';

/** Translates `key`, filling in `{placeholders}` from `values`. */
export function t(key: StringKey, values: Record<string, string | number> = {}): string {
  const text: string = isPortuguese ? portuguese[key] : key;
  return text.replace(/\{(\w+)\}/g, (placeholder, name: string) => String(values[name] ?? placeholder));
}

export function formatTime(date: Date): string {
  return date.toLocaleTimeString(locale?.languageTag, { hour: '2-digit', minute: '2-digit' });
}
