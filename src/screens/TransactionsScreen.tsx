import { Text, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { StatusChip } from '../components/StatusChip';
import { styles } from '../theme/styles';
import type { WorkflowState } from '../types';
import { formatCurrency } from '../utils/money';

export function TransactionsScreen({ state }: { state: WorkflowState }) {
  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>Ledger view</Text>
          <Text style={styles.pageTitle}>Transactions</Text>
          <Text style={styles.pageSubtitle}>Funding, fee, and settlement activity is loaded from database ledger rows.</Text>
        </View>
      </View>

      <GlassCard style={styles.widePanel}>
        <Text style={styles.panelTitle}>Activity ledger</Text>
        {state.transactions.length === 0 && <Text style={styles.lockedText}>No funding transactions are stored for this invoice yet.</Text>}
        {state.transactions.map((row) => (
          <View key={row.id} style={styles.tableRow}>
            <View style={{ flex: 1 }}>
              <Text style={styles.tablePrimary}>{row.label}</Text>
              <Text style={styles.tableSecondary}>{row.date}</Text>
            </View>
            <Text style={styles.tableAmount}>{formatCurrency(row.amountCents)}</Text>
            <StatusChip label={row.status} tone="green" />
          </View>
        ))}
      </GlassCard>
    </View>
  );
}