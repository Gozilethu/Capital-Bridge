import { createClient } from '@supabase/supabase-js';

const fallbackSupabaseUrl = 'https://wiwznymzaacfpnadbyen.supabase.co';
const fallbackSupabasePublishableKey = 'sb_publishable_MQ-zGB1QebUgsfP4sNVtdA_Qblaul8e';

const envSupabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL?.trim();
const envSupabasePublishableKey = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();

export const supabaseUrl = envSupabaseUrl || fallbackSupabaseUrl;
export const supabasePublishableKey = envSupabasePublishableKey || fallbackSupabasePublishableKey;

export const supabaseConfigError: string | null = null;

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


