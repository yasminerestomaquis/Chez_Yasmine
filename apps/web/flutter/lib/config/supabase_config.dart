/// Supabase project — public client configuration.
///
/// These are the anon/publishable key and project URL, meant to be embedded
/// in client apps (that is their purpose; access control is enforced by
/// Postgres RLS and NestJS, not by keeping this key secret). Never put the
/// service_role key here.
class SupabaseConfig {
  static const String url = 'https://tsebsulvhgttdwtgqfoj.supabase.co';
  static const String publishableKey = 'sb_publishable_VNCmuf3FemDWAhwIG65I0A_7fwhmcQX';
}
