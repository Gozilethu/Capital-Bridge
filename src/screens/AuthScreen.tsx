import { useState } from 'react';
import { Image, Pressable, Text, TextInput, View } from 'react-native';

import { LoadingCard } from '../components/LoadingCard';
import { styles } from '../theme/styles';
import type { Role } from '../types';

const accountTypes: Role[] = ['SME', 'Buyer', 'Financier'];

export function AuthScreen({
  configError,
  error,
  loading,
  loadingMessage,
  notice,
  onSignIn,
  onSignUp,
}: {
  configError: string | null;
  error: string | null;
  loading: boolean;
  loadingMessage: string | null;
  notice: string | null;
  onSignIn: (email: string, password: string) => Promise<void>;
  onSignUp: (input: {
    accountType: Role;
    email: string;
    fullName: string;
    organisationName: string;
    password: string;
  }) => Promise<void>;
}) {
  const [mode, setMode] = useState<'signup' | 'signin'>('signup');
  const [accountType, setAccountType] = useState<Role>('SME');
  const [email, setEmail] = useState('');
  const [fullName, setFullName] = useState('');
  const [organisationName, setOrganisationName] = useState('');
  const [password, setPassword] = useState('');

  async function submit() {
    if (mode === 'signin') {
      await onSignIn(email.trim(), password);
      return;
    }

    await onSignUp({
      accountType,
      email: email.trim(),
      fullName: fullName.trim(),
      organisationName: organisationName.trim(),
      password,
    });
  }

  const disabled =
    loading ||
    Boolean(configError) ||
    !email.trim() ||
    password.length < 6 ||
    (mode === 'signup' && (!fullName.trim() || !organisationName.trim()));

  return (
    <View style={styles.authShell}>
      <View style={styles.authPanel}>
        <View style={styles.brandRow}>
          <View style={styles.logoFrame}>
            <Image source={require('../../assets/icon.png')} style={styles.logo} />
          </View>
          <View>
            <Text style={styles.brand}>CapitalBridge</Text>
            <Text style={styles.headerSubline}>Secure invoice-to-cash workspace</Text>
          </View>
        </View>

        <Text style={styles.authTitle}>{mode === 'signup' ? 'Create your account' : 'Sign in'}</Text>
        <Text style={styles.authCopy}>An account and organisation workspace are required before any invoice, funding, or risk data can be viewed.</Text>

        {mode === 'signup' && (
          <>
            <Text style={styles.fieldLabel}>Full name</Text>
            <TextInput autoCapitalize="words" style={styles.textInput} value={fullName} onChangeText={setFullName} />

            <Text style={styles.fieldLabel}>Organisation name</Text>
            <TextInput autoCapitalize="words" style={styles.textInput} value={organisationName} onChangeText={setOrganisationName} />

            <Text style={styles.fieldLabel}>Account type</Text>
            <View style={styles.accountTypeRow}>
              {accountTypes.map((item) => (
                <Pressable
                  accessibilityRole="button"
                  key={item}
                  onPress={() => setAccountType(item)}
                  style={[styles.accountTypeButton, accountType === item && styles.accountTypeButtonActive]}
                >
                  <Text style={[styles.accountTypeText, accountType === item && styles.accountTypeTextActive]}>{item}</Text>
                </Pressable>
              ))}
            </View>
          </>
        )}

        <Text style={styles.fieldLabel}>Email</Text>
        <TextInput autoCapitalize="none" keyboardType="email-address" style={styles.textInput} value={email} onChangeText={setEmail} />

        <Text style={styles.fieldLabel}>Password</Text>
        <TextInput secureTextEntry style={styles.textInput} value={password} onChangeText={setPassword} />

        {(configError || error) && <Text style={styles.authError}>{configError ?? error}</Text>}
        {notice && !configError && !error && <Text style={styles.authNotice}>{notice}</Text>}
        {loading && <LoadingCard title="Working on your account" detail={loadingMessage ?? 'Connecting securely to Supabase.'} />}

        <Pressable accessibilityRole="button" disabled={disabled} onPress={submit} style={[styles.primaryButtonCompact, disabled && styles.disabled]}>
          <Text style={styles.primaryButtonText}>{loading ? 'Please wait...' : mode === 'signup' ? 'Create account' : 'Sign in'}</Text>
        </Pressable>

        <Pressable accessibilityRole="button" onPress={() => setMode(mode === 'signup' ? 'signin' : 'signup')} style={styles.authSwitch}>
          <Text style={styles.secondaryButtonText}>{mode === 'signup' ? 'Already have an account? Sign in' : 'Need an account? Create one'}</Text>
        </Pressable>
      </View>
    </View>
  );
}