import { Text, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { InfoRow } from '../components/InfoRow';
import { StatusChip } from '../components/StatusChip';
import { styles } from '../theme/styles';
import type { Role, WorkflowState } from '../types';
import { formatCurrency } from '../utils/money';
import { statusLabel, statusTone } from '../utils/workflow';

export function InvoicesScreen({ role, state }: { role: Role; state: WorkflowState }) {
  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>{role} workspace</Text>
          <Text style={styles.pageTitle}>Invoices</Text>
          <Text style={styles.pageSubtitle}>Invoice records are read from Supabase and display the database-owned verification and financing state.</Text>
        </View>
      </View>

      <GlassCard style={styles.widePanel}>
        <View style={styles.invoiceHeader}>
          <View style={styles.invoiceTitleGroup}>
            <Text style={styles.invoiceNumber}>{state.invoice.number}</Text>
            <Text style={styles.invoiceBuyer}>{state.invoice.buyer}</Text>
          </View>
          <StatusChip label={statusLabel(state.invoice.status)} tone={statusTone(state.invoice.status)} />
        </View>
        <View style={styles.amountBand}>
          <Text style={styles.amountLabel}>Invoice value</Text>
          <Text style={styles.amountValue}>{formatCurrency(state.invoice.amountCents)}</Text>
        </View>
        <InfoRow label="Supplier" value={state.invoice.supplier} />
        <InfoRow label="Purchase order" value={state.invoice.purchaseOrder || 'Not linked'} />
        <InfoRow label="Verification status" value={state.invoice.verificationStatus.replace(/_/g, ' ')} />
        <InfoRow label="Financing status" value={state.invoice.financingStatus.replace(/_/g, ' ')} />
        <InfoRow label="File" value={state.invoice.fileName} />
        <InfoRow label="File hash" value={state.invoice.fileHash ? `${state.invoice.fileHash.slice(0, 18)}...` : 'Pending'} />
        <InfoRow label="Invoice fingerprint" value={state.invoice.identityHash ? `${state.invoice.identityHash.slice(0, 18)}...` : 'Pending'} />
      </GlassCard>
    </View>
  );
}