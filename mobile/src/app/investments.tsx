import { SectionPlaceholder } from '@/components/section-placeholder';

export default function InvestmentsScreen() {
  return (
    <SectionPlaceholder
      title="Investments"
      sections={['Stocks', 'Bonds', 'Funds', 'FGC Watcher', 'Fund Comparison']}
    />
  );
}
