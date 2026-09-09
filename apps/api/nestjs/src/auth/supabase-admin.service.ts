import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * Seul point du code qui utilise la clé service_role (jamais exposée au
 * client — CLAUDE.md, « Règles Supabase / PostgreSQL »). Réservé aux
 * opérations que l'API Admin de Supabase Auth est seule à exposer, comme
 * l'invitation d'un utilisateur (voir UsersService) — tout le reste
 * (upload, URLs signées...) continue d'utiliser le jeton de l'utilisateur
 * authentifié via SupabaseStorageService.
 */
@Injectable()
export class SupabaseAdminService {
  private client: SupabaseClient | null = null;

  private getClient(): SupabaseClient {
    if (this.client) return this.client;
    const supabaseUrl = process.env.SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !serviceRoleKey) {
      throw new InternalServerErrorException('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY ne sont pas configurés');
    }
    this.client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    return this.client;
  }

  /**
   * Envoie l'e-mail d'invitation Supabase (lien magique pour choisir un mot
   * de passe). `metadata` devient `raw_user_meta_data` sur la ligne
   * `auth.users` créée — voir la migration `20260909120000_admin_invite_bootstrap.sql`
   * pour comment `invited_establishment_id`/`invited_role_id` y sont lus.
   * Lève une erreur brute (message Supabase tel quel) — UsersService décide
   * du type d'exception HTTP renvoyé.
   */
  async inviteUserByEmail(email: string, metadata: Record<string, string>): Promise<void> {
    const { error } = await this.getClient().auth.admin.inviteUserByEmail(email, { data: metadata });
    if (error) {
      throw new Error(error.message);
    }
  }
}
