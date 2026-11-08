import { SectionPlaceholder } from '@/components/section-placeholder';

export default function FinancesScreen() {
  return (
    <SectionPlaceholder
      title="Finances"
      sections={['Expenses', 'Bills', 'Insights', 'Categories & limits', 'Open Finance']}
    />
  );
}
