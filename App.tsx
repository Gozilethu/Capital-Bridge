import type { Session } from '@supabase/supabase-js';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useMemo, useState } from 'react';
import { Pressable, SafeAreaView, ScrollView, Text, useWindowDimensions, View } from 'react-native';

import { AppLayout } from './src/components/AppLayout';
import { navigationItems } from './src/config/navigation';
import { AuthScreen } from './src/screens/AuthScreen';
import { AuditScreen } from './src/screens/AuditScreen';
import { DashboardScreen } from './src/screens/DashboardScreen';
import { FundingScreen } from './src/screens/FundingScreen';
import { InvoicesScreen } from './src/screens/InvoicesScreen';
import { NotificationsScreen } from './src/screens/NotificationsScreen';
import { OnboardingScreen } from './src/screens/OnboardingScreen';
import { RiskVerificationScreen } from './src/screens/RiskVerificationScreen';
import { SettingsScreen } from './src/screens/SettingsScreen';
import { TransactionsScreen } from './src/screens/TransactionsScreen';
import { UploadInvoiceScreen } from './src/screens/UploadInvoiceScreen';
import { styles } from './src/theme/styles';
import type { LoadedWorkspace, Role, Tab, UploadInvoiceInput, WorkflowCommand } from './src/types';
import {
  acceptOfferInDatabase,
  advanceWorkflowInDatabase,
  completeUserOnboarding,
  createInvoiceUploadInDatabase,
  loadWorkspace,
  selectSubscriptionPlanInDatabase,
  updateRequestedAdvanceInDatabase,
} from './src/services/database';
import { supabase, supabaseConfigError } from './src/services/supabase';

export default function App() {
  const { width } = useWindowDimensions();
  const [activeTab, setActiveTab] = useState<Tab>('Upload');
  const [session, setSession] = useState<Session | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [workspaceData, setWorkspaceData] = useState<LoadedWorkspace | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const isDesktop = width >= 900;
  const role = workspaceData?.workspace.role ?? 'SME';
  const state = workspaceData?.state ?? null;
  const activeTabAllowed = useMemo(
    () => navigationItems.some((item) => item.tab === activeTab && item.roles.includes(role)),
    [activeTab, role],
  );

  useEffect(() => {
    let mounted = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) {
        return;
      }

      setSession(data.session);
      setAuthReady(true);
    });

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);

      if (!nextSession) {
        setWorkspaceData(null);
      }
    });

    return () => {
      mounted = false;
      data.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (authReady && session) {
      refreshWorkspace();
    }
  }, [authReady, session?.user.id]);

  useEffect(() => {
    if (!activeTabAllowed) {
      setActiveTab('Upload');
    }
  }, [activeTabAllowed]);

  async function refreshWorkspace() {
    setLoading(true);
    setError(null);

    try {
      setWorkspaceData(await loadWorkspace());
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setLoading(false);
    }
  }

  async function signUp(input: {
    accountType: Role;
    email: string;
    fullName: string;
    organisationName: string;
    password: string;
  }) {
    setLoading(true);
    setError(null);
    setNotice(null);

    try {
      const { data, error: signUpError } = await supabase.auth.signUp({
        email: input.email,
        password: input.password,
        options: {
          data: {
            account_type: input.accountType,
            full_name: input.fullName,
            organisation_name: input.organisationName,
          },
        },
      });

      if (signUpError) {
        throw new Error(signUpError.message);
      }

      if (data.session) {
        await completeUserOnboarding(input);
        await refreshWorkspace();
        setActiveTab('Upload');
      } else {
        setNotice('Account created. Confirm the email address, then sign in.');
      }
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setLoading(false);
    }
  }

  async function signIn(email: string, password: string) {
    setLoading(true);
    setError(null);
    setNotice(null);

    try {
      const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });

      if (signInError) {
        throw new Error(signInError.message);
      }

      await refreshWorkspace();
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setLoading(false);
    }
  }

  async function createWorkspace(input: { accountType: Role; fullName: string; organisationName: string }) {
    setLoading(true);
    setError(null);

    try {
      await completeUserOnboarding(input);
      await refreshWorkspace();
      setActiveTab('Upload');
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setLoading(false);
    }
  }

  async function signOut() {
    await supabase.auth.signOut();
    setActiveTab('Upload');
    setWorkspaceData(null);
    setError(null);
    setNotice(null);
  }

  async function uploadInvoice(input: UploadInvoiceInput) {
    if (!workspaceData) {
      return;
    }

    setLoading(true);
    setError(null);
    setNotice(null);

    try {
      await createInvoiceUploadInDatabase(workspaceData.workspace, input);
      await refreshWorkspace();
      setActiveTab('Invoices');
      setNotice('Invoice uploaded and stored in Supabase.');
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setLoading(false);
    }
  }

  async function selectPlan(planId: string) {
    setLoading(true);
    setError(null);
    setNotice(null);

    try {
      await selectSubscriptionPlanInDatabase(planId);
      await refreshWorkspace();
      setNotice('Plan updated for this workspace.');
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setLoading(false);
    }
  }

  async function sendCommand(command: WorkflowCommand) {
    if (!state) {
      return;
    }

    setLoading(true);
    setError(null);
    setNotice(null);

    try {
      await advanceWorkflowInDatabase(state, command);
      await refreshWorkspace();
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setLoading(false);
    }
  }

  async function updateAdvance(nextAmount: number) {
    if (!state || state.financingLocked) {
      return;
    }

    setLoading(true);
    setError(null);
    setNotice(null);

    try {
      const clampedAmount = Math.min(state.invoice.maxAdvanceCents, Math.max(1_000_000, nextAmount));
      await updateRequestedAdvanceInDatabase(state, clampedAmount);
      await refreshWorkspace();
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setLoading(false);
    }
  }

  async function acceptOffer(offerId: string) {
    setLoading(true);
    setError(null);
    setNotice(null);

    try {
      await acceptOfferInDatabase(offerId);
      await refreshWorkspace();
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setLoading(false);
    }
  }

  if (!authReady) {
    return <LoadingScreen label="Checking session..." />;
  }

  if (!session) {
    return <AuthScreen configError={supabaseConfigError} error={error} loading={loading} notice={notice} onSignIn={signIn} onSignUp={signUp} />;
  }

  if (!workspaceData) {
    return (
      <OnboardingScreen
        email={session.user.email ?? ''}
        error={error}
        loading={loading}
        onCreateWorkspace={createWorkspace}
        onSignOut={signOut}
      />
    );
  }

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="light" />
      <AppLayout
        accountName={workspaceData.workspace.accountName}
        activeTab={activeTab}
        isDesktop={isDesktop}
        organisationName={workspaceData.workspace.organisationName}
        role={workspaceData.workspace.role}
        setActiveTab={setActiveTab}
        onSignOut={signOut}
      >
        <ScrollView style={styles.scroll} contentContainerStyle={isDesktop && styles.contentWide} showsVerticalScrollIndicator={false}>
          {error && <Text style={styles.appError}>{error}</Text>}
          {notice && !error && <Text style={styles.appNotice}>{notice}</Text>}
          {loading && <Text style={styles.appNotice}>Syncing with Supabase...</Text>}
          {activeTab === 'Dashboard' &&
            (state ? (
              <DashboardScreen
                accountName={workspaceData.workspace.accountName}
                role={workspaceData.workspace.role}
                state={state}
                onCommand={sendCommand}
                onRefresh={refreshWorkspace}
              />
            ) : (
              <EmptyWorkspaceScreen setActiveTab={setActiveTab} />
            ))}
          {activeTab === 'Invoices' && (state ? <InvoicesScreen role={workspaceData.workspace.role} state={state} /> : <EmptyWorkspaceScreen setActiveTab={setActiveTab} />)}
          {activeTab === 'Upload' && (
            <UploadInvoiceScreen
              loading={loading}
              planStatus={workspaceData.planStatus}
              plans={workspaceData.plans}
              state={state}
              workspace={workspaceData.workspace}
              onCommand={sendCommand}
              onSelectPlan={selectPlan}
              onUploadInvoice={uploadInvoice}
            />
          )}
          {activeTab === 'Funding' && (state ? <FundingScreen state={state} updateAdvance={updateAdvance} onAcceptOffer={acceptOffer} onCommand={sendCommand} /> : <EmptyWorkspaceScreen setActiveTab={setActiveTab} />)}
          {activeTab === 'Risk' && (state ? <RiskVerificationScreen state={state} /> : <EmptyWorkspaceScreen setActiveTab={setActiveTab} />)}
          {activeTab === 'Transactions' && (state ? <TransactionsScreen state={state} /> : <EmptyWorkspaceScreen setActiveTab={setActiveTab} />)}
          {activeTab === 'Notifications' && (state ? <NotificationsScreen state={state} /> : <EmptyWorkspaceScreen setActiveTab={setActiveTab} />)}
          {activeTab === 'Audit' && (state ? <AuditScreen state={state} /> : <EmptyWorkspaceScreen setActiveTab={setActiveTab} />)}
          {activeTab === 'Settings' && <SettingsScreen state={state} workspace={workspaceData.workspace} />}
        </ScrollView>
      </AppLayout>
    </SafeAreaView>
  );
}

function EmptyWorkspaceScreen({ setActiveTab }: { setActiveTab: (tab: Tab) => void }) {
  return (
    <View style={styles.page}>
      <View style={styles.authPanel}>
        <Text style={styles.authTitle}>Upload your first invoice</Text>
        <Text style={styles.authCopy}>This workspace has no invoice records yet. Start by uploading a real PDF invoice.</Text>
        <Pressable accessibilityRole="button" onPress={() => setActiveTab('Upload')} style={styles.primaryButtonCompact}>
          <Text style={styles.primaryButtonText}>Go to upload</Text>
        </Pressable>
      </View>
    </View>
  );
}

function LoadingScreen({ label }: { label: string }) {
  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="light" />
      <View style={styles.authShell}>
        <View style={styles.loadingCard}>
          <Text style={styles.authTitle}>{label}</Text>
        </View>
      </View>
    </SafeAreaView>
  );
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : 'Something went wrong.';
}