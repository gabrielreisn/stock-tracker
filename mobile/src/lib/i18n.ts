import { getLocales } from 'expo-localization';

// Same convention as macOS/Resources/pt-BR.lproj/Localizable.strings: the English text is the key.
const portuguese = {
  "Fund holding": "Posição em fundo",
  "Your funds": "Seus fundos",
  "Add fund": "Adicionar fundo",
  "Edit fund": "Editar fundo",
  "Name": "Nome",
  "Shares": "Cotas",
  "Gross value": "Valor bruto",
  "Known gross value": "Valor bruto conhecido",
  "Share price": "Valor da cota",
  "Price date": "Data da cota",
  "Last month": "Último mês",
  "Year to date": "No ano",
  "Last 12 months": "Últimos 12 meses",
  "Tax exempt": "Isento de IR",
  "Taxable": "Tributável",
  "Statement": "Extrato",
  "Search by name or CNPJ": "Buscar por nome ou CNPJ",
  "Ascending": "Crescente",
  "Descending": "Decrescente",
  "Allocation by purpose": "Alocação por finalidade",
  "Selic / DI": "Selic / DI",
  "Private credit (CDI)": "Crédito privado (CDI)",
  "Inflation (IPCA)": "Inflação (IPCA)",
  "Infrastructure (FIP)": "Infraestrutura (FIP)",
  "Equities": "Ações",
  "Other": "Outros",
  "Automatic": "Automático",
  "Type": "Tipo",
  "Purpose": "Finalidade",
  "CNPJ": "CNPJ",
  "Delete": "Excluir",
  "Delete this fund?": "Excluir este fundo?",
  "Fund not found.": "Fundo não encontrado.",
  "A fund with this CNPJ already exists.": "Já existe um fundo com este CNPJ.",
  "Statement price (optional)": "Valor da cota no extrato (opcional)",
  "Demo account · Changes last for this session.": "Conta de demonstração · Alterações valem nesta sessão.",
  "{count} of {total} funds valued": "{count} de {total} fundos com valor conhecido",
  "No funds yet. Add a fund to get started.": "Nenhum fundo ainda. Adicione um fundo para começar.",
  "No matching funds.": "Nenhum fundo encontrado.",
  "Add statement prices to see allocation by value.": "Adicione os valores das cotas do extrato para ver a alocação por valor.",
  "Funds without prices are excluded from allocation.": "Fundos sem valor da cota ficam fora da alocação.",
  "Demo holdings have no CVM price history. Enter a statement price to value a fund. Returns require CVM history and remain unavailable. Values are gross, before income tax.": "As posições de demonstração não incluem histórico de cotas da CVM. Informe a cota do extrato para calcular o valor de um fundo. Os retornos dependem do histórico da CVM e estão indisponíveis. Os valores são brutos, antes do IR.",
  "Use a positive price and a valid date (YYYY-MM-DD), no later than today. Clear the price to remove the valuation.": "Use um valor positivo e uma data válida (AAAA-MM-DD), até hoje. Apague o valor da cota para remover a avaliação.",
  "Enter a 14-digit CNPJ, a name and a positive number of shares. Decimal comma or point accepted; omit thousands separators.": "Informe um CNPJ de 14 dígitos, um nome e uma quantidade positiva de cotas. Use vírgula ou ponto decimal, sem separadores de milhar.",

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
