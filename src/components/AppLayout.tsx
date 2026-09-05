import type { ReactNode } from 'react';
import { Image, Pressable, ScrollView, Text, View } from 'react-native';

import { navigationItems } from '../config/navigation';
import { styles } from '../theme/styles';
import type { Role, Tab } from '../types';
import { StatusChip } from './StatusChip';

export function AppLayout({
  accountName,
  activeTab,
  children,
  isDesktop,
  organisationName,
  role,
  setActiveTab,
  onSignOut,
}: {
  accountName: string;
  activeTab: Tab;
  children: ReactNode;
  isDesktop: boolean;
  organisationName: string;
  role: Role;
  setActiveTab: (tab: Tab) => void;
  onSignOut: () => void;
}) {
  const availableItems = navigationItems.filter((item) => item.roles.includes(role));

  return (
    <View style={styles.appBackground}>
      <TopBar accountName={accountName} organisationName={organisationName} role={role} onSignOut={onSignOut} />
      <View style={styles.workspace}>
        {isDesktop && <Sidebar activeTab={activeTab} items={availableItems} setActiveTab={setActiveTab} />}
        <View style={styles.mainSurface}>{children}</View>
      </View>
      {!isDesktop && <MobileNavigation activeTab={activeTab} items={availableItems} setActiveTab={setActiveTab} />}
    </View>
  );
}

function TopBar({
  accountName,
  organisationName,
  role,
  onSignOut,
}: {
  accountName: string;
  organisationName: string;
  role: Role;
  onSignOut: () => void;
}) {
  return (
    <View style={styles.topBar}>
      <View style={styles.brandLockup}>
        <View style={styles.logoFrame}>
          <Image source={require('../../assets/icon.png')} style={styles.logo} />
        </View>
        <View>
          <Text style={styles.brand}>CapitalBridge</Text>
          <Text style={styles.headerSubline}>{organisationName}</Text>
        </View>
      </View>
      <View style={styles.searchBox}>
        <Text style={styles.searchText}>Search invoices, buyers, funding...</Text>
      </View>
      <View style={styles.topActions}>
        <StatusChip label={role} tone="slate" />
        <Text style={styles.accountName}>{accountName}</Text>
        <Pressable accessibilityRole="button" onPress={onSignOut} style={styles.signOutButton}>
          <Text style={styles.signOutText}>Sign out</Text>
        </Pressable>
      </View>
    </View>
  );
}

function Sidebar({
  activeTab,
  items,
  setActiveTab,
}: {
  activeTab: Tab;
  items: { tab: Tab; label: string }[];
  setActiveTab: (tab: Tab) => void;
}) {
  return (
    <View style={styles.sidebar}>
      <Text style={styles.sidebarLabel}>Workspace</Text>
      {items.map((item) => (
        <Pressable
          accessibilityRole="button"
          key={item.tab}
          onPress={() => setActiveTab(item.tab)}
          style={[styles.sidebarItem, activeTab === item.tab && styles.sidebarItemActive]}
        >
          <Text style={[styles.sidebarGlyph, activeTab === item.tab && styles.sidebarGlyphActive]}>{navGlyph(item.tab)}</Text>
          <Text style={[styles.sidebarText, activeTab === item.tab && styles.sidebarTextActive]}>{item.label}</Text>
        </Pressable>
      ))}
    </View>
  );
}

function MobileNavigation({
  activeTab,
  items,
  setActiveTab,
}: {
  activeTab: Tab;
  items: { tab: Tab; label: string }[];
  setActiveTab: (tab: Tab) => void;
}) {
  return (
    <View style={styles.mobileNavShell}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.mobileNavContent}>
        {items.map((item) => (
          <Pressable
            accessibilityRole="button"
            key={item.tab}
            onPress={() => setActiveTab(item.tab)}
            style={[styles.mobileNavItem, activeTab === item.tab && styles.mobileNavItemActive]}
          >
            <Text style={[styles.mobileNavGlyph, activeTab === item.tab && styles.mobileNavGlyphActive]}>{navGlyph(item.tab)}</Text>
            <Text style={[styles.mobileNavText, activeTab === item.tab && styles.mobileNavTextActive]}>{item.label}</Text>
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}

function navGlyph(tab: Tab) {
  if (tab === 'Dashboard') {
    return '$';
  }

  if (tab === 'Invoices') {
    return '#';
  }

  if (tab === 'Upload') {
    return '+';
  }

  if (tab === 'Funding') {
    return '%';
  }

  if (tab === 'Risk') {
    return '!';
  }

  if (tab === 'Transactions') {
    return '=';
  }

  if (tab === 'Notifications') {
    return '.';
  }

  if (tab === 'Audit') {
    return '@';
  }

  return '*';
}