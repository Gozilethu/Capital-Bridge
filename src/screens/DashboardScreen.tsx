import { Pressable, Text, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { MetricCard } from '../components/MetricCard';
import { StatusChip } from '../components/StatusChip';
import { styles } from '../theme/styles';
import type { Role, WorkflowCommand, WorkflowState } from '../types';
import { calculateFee, formatCurrency } from '../utils/money';
import { calculateTrustScore, riskBand } from '../utils/risk';
import {
  availableWorkingCapitalCents,
  commandLabel,
  nextCommandForState,
  statusLabel,
  statusTone,
  upcomingSettlementCents,
} from '../utils/workflow';

export function DashboardScreen({
  accountName,
  role,
  state,
  onCommand,
  onRefresh,
}: {
  accountName: string;
  role: Role;
  state: WorkflowState;
  onCommand: (command: WorkflowCommand) => void;
  onRefresh: () => void;
}) {
  const nextCommand = nextCommandForState(state);
  const acceptedOffer = state.offers.find((offer) => offer.id === state.acceptedOfferId) ?? state.offers[0];
  const feeCents = calculateFee(state.advanceCents, acceptedOffer?.feeBps ?? 0);
  const trustScore = state.riskFactors.length > 0 ? calculateTrustScore(state.riskFactors) : null;
  const attention = state.riskFactors.find((factor) => factor.kind === 'attention');
  const latestEvent = state.transactionEvents[state.transactionEvents.length - 1] ?? null;

  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>{role} account</Text>
          <Text style={styles.pageTitle}>Good morning, {accountName}</Text>
          <Text style={styles.pageSubtitle}>Your cash position is backed by verified receivable evidence, financier offers, and settlement monitoring.</Text>
        </View>
        <View style={styles.pageActions}>
          <StatusChip label={statusLabel(state.invoice.status)} tone={statusTone(state.invoice.status)} />
          <StatusChip label="Database state" tone="slate" />
        </View>
      </View>

      <View style={styles.metricGrid}>
        <MetricCard
          accent="#45b7a6"
          helper="Calculated from server-owned receivable state"
          label="Available working capital"
          valueCents={availableWorkingCapitalCents(state)}
        />
        <MetricCard
          accent="#7aa7ff"
          helper={`${state.invoice.dueDays} day terms, buyer ${state.invoice.verificationStatus.toLowerCase()}`}
          label="Outstanding invoices"
          valueCents={state.invoice.outstandingCents}
        />
        <MetricCard
          accent="#d98b5f"
          helper={state.financingLocked ? 'Invoice financing lock active' : 'No active financing lock'}
          label="Active financing"
          valueCents={state.financingLocked ? state.advanceCents : 0}
        />
        <MetricCard
          accent="#e5c15f"
          helper={state.invoice.financingStatus === 'ACTIVE' ? 'Expected on buyer payment' : 'No settlement due yet'}
          label="Upcoming settlements"
          valueCents={upcomingSettlementCents(state, feeCents)}
        />
      </View>

      <View style={styles.commandRow}>
        <Pressable
          accessibilityRole="button"
          disabled={!nextCommand}
          onPress={() => nextCommand && onCommand(nextCommand)}
          style={[styles.primaryButton, !nextCommand && styles.disabled]}
        >
          <Text style={styles.primaryButtonText}>{commandLabel(nextCommand)}</Text>
        </Pressable>
        <Pressable accessibilityRole="button" onPress={onRefresh} style={styles.secondaryButton}>
          <Text style={styles.secondaryButtonText}>Refresh database</Text>
        </Pressable>
      </View>

      <View style={styles.contentGrid}>
        <GlassCard style={styles.widePanel}>
          <Text style={styles.panelTitle}>Recent invoices</Text>
          <View style={styles.tableRow}>
            <View style={{ flex: 1.4 }}>
              <Text style={styles.tablePrimary}>{state.invoice.number}</Text>
              <Text style={styles.tableSecondary}>{state.invoice.buyer}</Text>
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.tableAmount}>{formatCurrency(state.invoice.amountCents)}</Text>
              <Text style={styles.tableAction}>{state.invoice.financingStatus === 'ELIGIBLE' ? 'Get funding' : 'View details'}</Text>
            </View>
            <StatusChip label={statusLabel(state.invoice.status)} tone={statusTone(state.invoice.status)} />
          </View>
        </GlassCard>

        <GlassCard style={styles.sidePanel}>
          <Text style={styles.panelTitle}>Transaction evidence</Text>
          <Text style={styles.amountValue}>{trustScore === null ? 'Pending' : `${trustScore} / 100`}</Text>
          <Text style={styles.tableSecondary}>
            {trustScore === null ? 'Risk factors will appear after the database risk job runs.' : `${riskBand(trustScore)} risk based on verification evidence.`}
          </Text>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Latest evidence</Text>
            <Text style={styles.infoValue}>{latestEvent?.label ?? 'No monitoring event yet'}</Text>
          </View>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Primary attention</Text>
            <Text style={styles.infoValue}>{attention?.label ?? 'No open attention item'}</Text>
          </View>
        </GlassCard>
      </View>
    </View>
  );
}