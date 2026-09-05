import { createElement, useState } from 'react';
import { Platform, Pressable, Text, TextInput, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { InfoRow } from '../components/InfoRow';
import { StatusChip } from '../components/StatusChip';
import { styles } from '../theme/styles';
import type { OrganisationWorkspace, PlanStatus, SubscriptionPlan, UploadInvoiceInput, WorkflowCommand, WorkflowState } from '../types';
import { formatCurrency } from '../utils/money';
import { commandLabel, hasReached, nextCommandForState } from '../utils/workflow';

export function UploadInvoiceScreen({
  loading,
  planStatus,
  plans,
  state,
  workspace,
  onCommand,
  onSelectPlan,
  onUploadInvoice,
}: {
  loading: boolean;
  planStatus: PlanStatus | null;
  plans: SubscriptionPlan[];
  state: WorkflowState | null;
  workspace: OrganisationWorkspace;
  onCommand: (command: WorkflowCommand) => void;
  onSelectPlan: (planId: string) => void;
  onUploadInvoice: (input: UploadInvoiceInput) => void;
}) {
  const [amount, setAmount] = useState('');
  const [buyerName, setBuyerName] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [invoiceNumber, setInvoiceNumber] = useState('');
  const [purchaseOrderNumber, setPurchaseOrderNumber] = useState('');
  const [requestedAdvance, setRequestedAdvance] = useState('');
  const [supplierName, setSupplierName] = useState(workspace.organisationName);
  const [localError, setLocalError] = useState<string | null>(null);
  const nextCommand = state ? nextCommandForState(state) : null;
  const scanBlocked = nextCommand === 'START_SCAN' && Boolean(planStatus?.requiresPayment);
  const canAdvance = Boolean(nextCommand) && !scanBlocked;
  const amountCents = parseMoneyToCents(amount);
  const requestedAdvanceCents = parseMoneyToCents(requestedAdvance);
  const canUpload = Boolean(file && invoiceNumber.trim() && buyerName.trim() && supplierName.trim() && amountCents > 0 && dueDate.trim());
  const quotaUsed = planStatus?.scansUsed ?? 0;
  const quotaLimit = planStatus?.scanLimit ?? 10;
  const quotaRemaining = planStatus?.scansRemaining ?? Math.max(quotaLimit - quotaUsed, 0);

  function chooseFile() {
    setLocalError(null);

    if (Platform.OS !== 'web' || typeof document === 'undefined') {
      setLocalError('PDF upload is currently enabled for the web build.');
      return;
    }

    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'application/pdf,.pdf';
    input.onchange = () => {
      const nextFile = input.files?.[0] ?? null;

      if (!nextFile) {
        return;
      }

      if (!nextFile.name.toLowerCase().endsWith('.pdf') || (nextFile.type && nextFile.type !== 'application/pdf')) {
        setLocalError('Choose a PDF invoice file.');
        return;
      }

      if (nextFile.size > 10 * 1024 * 1024) {
        setLocalError('PDF invoices must be 10 MB or smaller.');
        return;
      }

      setFile(nextFile);
    };
    input.click();
  }

  function submitUpload() {
    if (!file || !canUpload) {
      setLocalError('Select a PDF and complete the invoice fields.');
      return;
    }

    if (requestedAdvanceCents > amountCents) {
      setLocalError('Requested advance cannot be more than the invoice amount.');
      return;
    }

    setLocalError(null);
    onUploadInvoice({
      amountCents,
      buyerName,
      dueDate,
      file,
      invoiceNumber,
      purchaseOrderNumber,
      requestedAdvanceCents: requestedAdvanceCents || Math.round(amountCents * 0.3),
      supplierName,
    });
  }

  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>Secure document intake</Text>
          <Text style={styles.pageTitle}>Upload Invoice</Text>
          <Text style={styles.pageSubtitle}>Upload a real PDF invoice and store its metadata, hash, duplicate checks, and workflow state in Supabase.</Text>
        </View>
        <StatusChip label={`${quotaRemaining} scans left`} tone={quotaRemaining > 0 ? 'green' : 'amber'} />
      </View>

      <View style={styles.contentGrid}>
        <GlassCard style={styles.widePanel}>
          <Text style={styles.panelTitle}>Invoice file and details</Text>
          <View style={styles.uploadFormGrid}>
            <View style={styles.formColumn}>
              <Text style={styles.fieldLabel}>PDF invoice</Text>
              <Pressable accessibilityRole="button" onPress={chooseFile} style={styles.uploadButtonDark}>
                <Text style={styles.uploadButtonDarkText}>{file ? file.name : 'Choose PDF'}</Text>
              </Pressable>
              {file && <Text style={styles.tableSecondary}>{Math.ceil(file.size / 1024)} KB selected</Text>}

              <Text style={styles.fieldLabel}>Invoice number</Text>
              <TextInput autoCapitalize="characters" style={styles.textInput} value={invoiceNumber} onChangeText={setInvoiceNumber} />

              <Text style={styles.fieldLabel}>Purchase order</Text>
              <TextInput autoCapitalize="characters" style={styles.textInput} value={purchaseOrderNumber} onChangeText={setPurchaseOrderNumber} />
            </View>

            <View style={styles.formColumn}>
              <Text style={styles.fieldLabel}>Supplier</Text>
              <TextInput style={styles.textInput} value={supplierName} onChangeText={setSupplierName} />

              <Text style={styles.fieldLabel}>Buyer / customer</Text>
              <TextInput style={styles.textInput} value={buyerName} onChangeText={setBuyerName} />

              <Text style={styles.fieldLabel}>Due date</Text>
              <DueDateInput value={dueDate} onChange={setDueDate} />
            </View>

            <View style={styles.formColumn}>
              <Text style={styles.fieldLabel}>Invoice amount</Text>
              <TextInput keyboardType="decimal-pad" placeholder="100000.00" placeholderTextColor="#c4ced8" style={styles.textInput} value={amount} onChangeText={setAmount} />

              <Text style={styles.fieldLabel}>Requested advance</Text>
              <TextInput keyboardType="decimal-pad" placeholder="30000.00" placeholderTextColor="#c4ced8" style={styles.textInput} value={requestedAdvance} onChangeText={setRequestedAdvance} />

              <Pressable accessibilityRole="button" disabled={!canUpload || loading} onPress={submitUpload} style={[styles.primaryButtonCompact, (!canUpload || loading) && styles.disabled]}>
                <Text style={styles.primaryButtonText}>{loading ? 'Uploading...' : 'Upload invoice'}</Text>
              </Pressable>
            </View>
          </View>
          {localError && <Text style={styles.authError}>{localError}</Text>}
        </GlassCard>

        <GlassCard style={styles.sidePanel}>
          <Text style={styles.panelTitle}>Monthly scanning</Text>
          <InfoRow label="Current plan" value={planStatus?.planName ?? 'Free Scanner'} />
          <InfoRow label="Scans used" value={`${quotaUsed} / ${quotaLimit}`} />
          <InfoRow label="Remaining" value={`${quotaRemaining}`} />
          {quotaRemaining <= 0 && <Text style={styles.authError}>Free scanner limit reached. Choose a plan before scanning more invoices.</Text>}
        </GlassCard>
      </View>

      <GlassCard style={styles.widePanel}>
        <Text style={styles.panelTitle}>Plans</Text>
        <View style={styles.planGrid}>
          {plans.map((plan) => (
            <Pressable
              accessibilityRole="button"
              key={plan.id}
              onPress={() => onSelectPlan(plan.id)}
              style={[styles.planCard, planStatus?.planId === plan.id && styles.planCardActive]}
            >
              <View style={styles.taskCardTop}>
                <Text style={styles.offerTitle}>{plan.name}</Text>
                <StatusChip label={planStatus?.planId === plan.id ? 'Current' : `${plan.scanLimit} scans`} tone={planStatus?.planId === plan.id ? 'green' : 'slate'} />
              </View>
              <Text style={styles.amountValue}>{plan.monthlyPriceCents === 0 ? 'Free' : formatCurrency(plan.monthlyPriceCents)}</Text>
              <Text style={styles.tableSecondary}>{plan.description}</Text>
              {plan.benefits.map((benefit) => (
                <Text key={benefit} style={styles.planBenefit}>{benefit}</Text>
              ))}
            </Pressable>
          ))}
        </View>
      </GlassCard>

      {state && (
        <GlassCard style={styles.widePanel}>
          <Text style={styles.panelTitle}>Latest invoice pipeline</Text>
          <SecurityRow complete label="Database file record" detail={state.invoice.fileName} />
          <SecurityRow complete={hasReached(state.invoice.status, 'SCANNING')} label="MIME and magic bytes checked" detail="Stored by validation job" />
          <SecurityRow complete={hasReached(state.invoice.status, 'SCANNING')} label="SHA-256 hash generated" detail={state.invoice.fileHash ? state.invoice.fileHash.slice(0, 28) : 'Pending'} />
          <SecurityRow complete={hasReached(state.invoice.status, 'SCANNING')} label="Monthly scan usage recorded" detail={`${quotaUsed} used this month`} />
          <SecurityRow complete={hasReached(state.invoice.status, 'EXTRACTED')} label="Invoice fields extracted" detail="Extraction rows stored in Supabase" />
          <SecurityRow complete={hasReached(state.invoice.status, 'VERIFYING')} label="Buyer verification" detail="ERP connector checks PO, supplier, amount, and status" />
          <Pressable
            accessibilityRole="button"
            disabled={!canAdvance}
            onPress={() => nextCommand && !scanBlocked && onCommand(nextCommand)}
            style={[styles.primaryButtonCompact, !canAdvance && styles.disabled]}
          >
            <Text style={styles.primaryButtonText}>{scanBlocked ? 'Choose a plan to scan' : commandLabel(nextCommand)}</Text>
          </Pressable>
        </GlassCard>
      )}
    </View>
  );
}

function DueDateInput({ onChange, value }: { onChange: (value: string) => void; value: string }) {
  if (Platform.OS === 'web' && typeof document !== 'undefined') {
    return createElement('input', {
      'aria-label': 'Due date',
      min: new Date().toISOString().slice(0, 10),
      onChange: (event) => onChange((event.target as HTMLInputElement).value),
      style: webDateInputStyle,
      type: 'date',
      value,
    });
  }

  return <TextInput placeholder="YYYY-MM-DD" style={styles.textInput} value={value} onChangeText={onChange} />;
}

const webDateInputStyle = {
  backgroundColor: '#ffffff',
  border: '1px solid #cfd9e5',
  borderRadius: 8,
  boxSizing: 'border-box' as const,
  color: '#102337',
  fontFamily: 'inherit',
  fontSize: 14,
  fontWeight: 700,
  height: 46,
  minHeight: 46,
  outline: 'none',
  padding: '0 12px',
  width: '100%',
};
function SecurityRow({ complete, detail, label }: { complete: boolean; detail: string; label: string }) {
  return (
    <View style={styles.checkRow}>
      <StatusChip label={complete ? 'Complete' : 'Pending'} tone={complete ? 'green' : 'neutral'} />
      <Text style={styles.checkLabel}>{label}</Text>
      <Text style={styles.checkValue}>{detail}</Text>
    </View>
  );
}

function parseMoneyToCents(value: string) {
  const normalized = value.replace(/[^0-9.]/g, '');
  const parsed = Number(normalized);

  if (!Number.isFinite(parsed)) {
    return 0;
  }

  return Math.round(parsed * 100);
}