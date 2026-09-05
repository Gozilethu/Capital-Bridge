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
          <Text style={styles.pageKicker}>Closed-loop ledger</Text>
          <Text style={styles.pageTitle}>Transactions</Text>
          <Text style={styles.pageSubtitle}>CapitalBridge tracks the commercial transaction from PO and delivery evidence through funding, buyer payment, and settlement.</Text>
        </View>
      </View>

      <GlassCard style={styles.widePanel}>
        <Text style={styles.panelTitle}>Transaction monitoring</Text>
        {state.transactionEvents.length === 0 && <Text style={styles.lockedText}>No monitoring events are stored for this invoice yet.</Text>}
        {state.transactionEvents.map((event) => (
          <View key={event.id} style={styles.tableRow}>
            <StatusChip label={event.phase} tone={event.tone} />
            <View style={{ flex: 1 }}>
              <Text style={styles.tablePrimary}>{event.label}</Text>
              <Text style={styles.tableSecondary}>{event.detail}</Text>
              <Text style={styles.tableSecondary}>{event.time}</Text>
            </View>
            <StatusChip label={event.status} tone={event.tone} />
          </View>
        ))}
      </GlassCard>

      <GlassCard style={styles.widePanel}>
        <Text style={styles.panelTitle}>Funding ledger</Text>
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