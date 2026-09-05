import { createClient } from '@supabase/supabase-js';

const fallbackSupabaseUrl = 'https://wiwznymzaacfpnadbyen.supabase.co';
const fallbackSupabasePublishableKey = 'sb_publishable_MQ-zGB1QebUgsfP4sNVtdA_Qblaul8e';

export const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL ?? fallbackSupabaseUrl;
export const supabasePublishableKey =
  process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? fallbackSupabasePublishableKey;

export const supabaseConfigError =
  !supabaseUrl || !supabasePublishableKey
    ? 'Missing EXPO_PUBLIC_SUPABASE_URL or EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY.'
    : null;

export const supabase = createClient(
  supabaseUrl || 'https://example.supabase.co',
  supabasePublishableKey || 'missing-publishable-key',
  {
    auth: {
      autoRefreshToken: true,
      detectSessionInUrl: true,
      persistSession: true,
    },
  },
);
