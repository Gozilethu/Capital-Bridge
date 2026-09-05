import type { NavigationItem, Role } from '../types';

export const defaultRole: Role = 'SME';

export const navigationItems: NavigationItem[] = [
  { tab: 'Dashboard', label: 'Dashboard', roles: ['SME', 'Buyer', 'Financier', 'Admin'] },
  { tab: 'Invoices', label: 'Invoices', roles: ['SME', 'Buyer', 'Financier', 'Admin'] },
  { tab: 'Upload', label: 'Upload Invoice', roles: ['SME', 'Admin'] },
  { tab: 'Funding', label: 'Funding', roles: ['SME', 'Financier', 'Admin'] },
  { tab: 'Risk', label: 'Risk & Verification', roles: ['SME', 'Buyer', 'Financier', 'Admin'] },
  { tab: 'Transactions', label: 'Transactions', roles: ['SME', 'Financier', 'Admin'] },
  { tab: 'Notifications', label: 'Notifications', roles: ['SME', 'Buyer', 'Financier', 'Admin'] },
  { tab: 'Audit', label: 'Audit Trail', roles: ['Financier', 'Admin'] },
  { tab: 'Settings', label: 'Settings', roles: ['SME', 'Buyer', 'Financier', 'Admin'] },
];