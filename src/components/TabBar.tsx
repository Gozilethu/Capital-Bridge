import { Pressable, Text } from 'react-native';

import { navigationItems } from '../config/navigation';
import { styles } from '../theme/styles';
import type { Role, Tab } from '../types';

export function TabBar({ activeTab, role, setActiveTab }: { activeTab: Tab; role: Role; setActiveTab: (tab: Tab) => void }) {
  return (
    <>
      {navigationItems
        .filter((item) => item.roles.includes(role))
        .map(({ tab }) => (
          <Pressable
            accessibilityRole="button"
            key={tab}
            onPress={() => setActiveTab(tab)}
            style={[styles.tabButton, activeTab === tab && styles.tabButtonActive]}
          >
            <Text style={[styles.tabSymbol, activeTab === tab && styles.tabSymbolActive]}>{tab.charAt(0)}</Text>
            <Text style={[styles.tabText, activeTab === tab && styles.tabTextActive]}>{tab}</Text>
          </Pressable>
        ))}
    </>
  );
}