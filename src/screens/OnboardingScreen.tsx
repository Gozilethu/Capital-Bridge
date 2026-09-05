import { useState } from 'react';
import { Pressable, Text, TextInput, View } from 'react-native';

import { styles } from '../theme/styles';
import type { Role } from '../types';

const accountTypes: Role[] = ['SME', 'Buyer', 'Financier'];

export function OnboardingScreen({
  email,
  error,
  loading,
  onCreateWorkspace,
  onSignOut,
}: {
  email: string;
  error: string | null;
  loading: boolean;
  onCreateWorkspace: (input: { accountType: Role; fullName: string; organisationName: string }) => Promise<void>;
  onSignOut: () => Promise<void>;
}) {
  const [accountType, setAccountType] = useState<Role>('SME');
  const [fullName, setFullName] = useState('');
  const [organisationName, setOrganisationName] = useState('');
  const disabled = loading || !fullName.trim() || !organisationName.trim();

  return (
    <View style={styles.authShell}>
      <View style={styles.authPanel}>
        <Text style={styles.authTitle}>Create your workspace</Text>
        <Text style={styles.authCopy}>{email} is signed in. Create an organisation workspace before accessing CapitalBridge records.</Text>

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

        {error && <Text style={styles.authError}>{error}</Text>}

        <Pressable
          accessibilityRole="button"
          disabled={disabled}
          onPress={() => onCreateWorkspace({ accountType, fullName, organisationName })}
          style={[styles.primaryButtonCompact, disabled && styles.disabled]}
        >
          <Text style={styles.primaryButtonText}>{loading ? 'Creating...' : 'Create workspace'}</Text>
        </Pressable>

        <Pressable accessibilityRole="button" onPress={onSignOut} style={styles.authSwitch}>
          <Text style={styles.secondaryButtonText}>Sign out</Text>
        </Pressable>
      </View>
    </View>
  );
}