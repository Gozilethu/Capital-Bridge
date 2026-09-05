import { Pressable, Text, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { InfoRow } from '../components/InfoRow';
import { OfferCard } from '../components/OfferCard';
import { StatusChip } from '../components/StatusChip';
import { styles } from '../theme/styles';
import type { WorkflowCommand, WorkflowState } from '../types';
import { calculateFee, formatCurrency } from '../utils/money';
import { hasReached } from '../utils/workflow';

export function FundingScreen({
  state,
  updateAdvance,
  onAcceptOffer,
  onCommand,
}: {
  state: WorkflowState;
  updateAdvance: (nextAmount: number) => void;
  onAcceptOffer: (offerId: string) => void;
  onCommand: (command: WorkflowCommand) => void;
}) {
  const canAdjustAdvance = state.invoice.status === 'FINANCE_ELIGIBLE' && state.offers.length > 0 && !state.financingLocked;
  const canAcceptOffer = state.invoice.status === 'FINANCE_ELIGIBLE' && !state.financingLocked;
  const acceptedOffer = state.offers.find((offer) => offer.id === state.acceptedOfferId) ?? null;
  const previewOffer = acceptedOffer ?? state.offers[0] ?? null;
  const feeCents = previewOffer ? calculateFee(state.advanceCents, previewOffer.feeBps) : 0;
  const expectedRemainderCents = Math.max(state.invoice.amountCents - state.advanceCents - feeCents, 0);

  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>Transparent pricing</Text>
          <Text style={styles.pageTitle}>Funding</Text>
          <Text style={styles.pageSubtitle}>Offer availability, acceptance locks, disbursement, and settlement are all read from Supabase.</Text>
        </View>
        <StatusChip label={state.financingLocked ? 'Financing lock active' : 'No lock'} tone={state.financingLocked ? 'green' : 'neutral'} />
      </View>

      <GlassCard style={styles.widePanel}>
        <Text style={styles.panelTitle}>Funding amount</Text>
        <View style={styles.fundingPanel}>
          <View style={styles.fundingCopy}>
            <Text style={styles.smallCaps}>Requested advance</Text>
            <Text style={styles.fundingAmount}>{formatCurrency(state.advanceCents)}</Text>
            <Text style={styles.fundingCaption}>Maximum available {formatCurrency(state.invoice.maxAdvanceCents)}</Text>
          </View>
          <View style={styles.stepper}>
            <Pressable
              accessibilityLabel="Decrease advance amount"
              disabled={!canAdjustAdvance}
              onPress={() => updateAdvance(state.advanceCents - 500_000)}
              style={[styles.stepperButton, !canAdjustAdvance && styles.disabled]}
            >
              <Text style={styles.stepperText}>-</Text>
            </Pressable>
            <Pressable
              accessibilityLabel="Increase advance amount"
              disabled={!canAdjustAdvance}
              onPress={() => updateAdvance(state.advanceCents + 500_000)}
              style={[styles.stepperButton, !canAdjustAdvance && styles.disabled]}
            >
              <Text style={styles.stepperText}>+</Text>
            </Pressable>
          </View>
        </View>
        <InfoRow label="Invoice value" value={formatCurrency(state.invoice.amountCents)} />
        <InfoRow label="You receive today" value={formatCurrency(state.advanceCents)} />
        <InfoRow label="Financing fee" value={formatCurrency(feeCents)} />
        <InfoRow label="Total settlement obligation" value={formatCurrency(state.advanceCents + feeCents)} />
        <InfoRow label="Expected invoice balance to SME" value={formatCurrency(expectedRemainderCents)} />
      </GlassCard>

      {!hasReached(state.invoice.status, 'FINANCE_ELIGIBLE') && (
        <GlassCard style={styles.sidePanel}>
          <StatusChip label="Verification required" tone="amber" />
          <Text style={styles.lockedText}>Funding opens after extraction, ERP verification, duplicate checks, and risk assessment have been recorded in Supabase.</Text>
        </GlassCard>
      )}

      {hasReached(state.invoice.status, 'FINANCE_ELIGIBLE') && state.offers.length === 0 && (
        <GlassCard style={styles.sidePanel}>
          <StatusChip label="No offers" tone="neutral" />
          <Text style={styles.lockedText}>No financing offers are stored for this invoice yet.</Text>
        </GlassCard>
      )}

      {hasReached(state.invoice.status, 'FINANCE_ELIGIBLE') &&
        state.offers.map((offer) => (
          <OfferCard
            accepted={state.acceptedOfferId === offer.id}
            disabled={!canAcceptOffer || Boolean(state.acceptedOfferId && state.acceptedOfferId !== offer.id)}
            key={offer.id}
            offer={offer}
            selectedAmountCents={state.advanceCents}
            onAccept={() => onAcceptOffer(offer.id)}
          />
        ))}

      {state.invoice.status === 'OFFER_ACCEPTED' && (
        <Pressable accessibilityRole="button" onPress={() => onCommand('DISBURSE_FUNDS')} style={styles.primaryButtonCompact}>
          <Text style={styles.primaryButtonText}>Record disbursement</Text>
        </Pressable>
      )}
      {state.invoice.status === 'FUNDED' && (
        <Pressable accessibilityRole="button" onPress={() => onCommand('SETTLE_INVOICE')} style={styles.primaryButtonCompact}>
          <Text style={styles.primaryButtonText}>Record settlement</Text>
        </Pressable>
      )}
    </View>
  );
}