import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * Où un lien Supabase (invitation ou réinitialisation) redirige une fois le
 * jeton vérifié — sans `redirectTo` explicite, Supabase retombe sur le
 * « Site URL » du projet, resté sur `localhost:3000` (utile en dev, jamais
 * en production) : un lien cliqué depuis un vrai appareil échouait alors en
 * `ERR_CONNECTION_REFUSED` (rencontré en conditions réelles le 2026-09-09,
 * sur missakey1@gmail.com). Même origine que celle whitelistée pour CORS
 * dans main.ts.
 */
const APP_REDIRECT_URL = 'https://chez-yasmine-two.vercel.app';

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
  async inviteUserByEmail(email: string, metadata: Record<string, string | boolean>): Promise<void> {
    const { error } = await this.getClient().auth.admin.inviteUserByEmail(email, {
      data: metadata,
      redirectTo: APP_REDIRECT_URL,
    });
    if (error) {
      throw new Error(error.message);
    }
  }

  /**
   * Même effet que inviteUserByEmail (crée le compte, mêmes métadonnées) mais
   * ne passe jamais par le service d'e-mail de Supabase — utile quand son
   * quota gratuit partagé est atteint (voir docs/api/users.md). Renvoie le
   * lien tel quel ; à afficher/copier côté UI pour que l'appelant l'envoie
   * lui-même par le canal de son choix (jamais Claude qui l'envoie à sa
   * place).
   */
  async generateInviteLink(email: string, metadata: Record<string, string | boolean>): Promise<string> {
    const { data, error } = await this.getClient().auth.admin.generateLink({
      type: 'invite',
      email,
      options: { data: metadata, redirectTo: APP_REDIRECT_URL },
    });
    if (error || !data.properties?.action_link) {
      throw new Error(error?.message ?? 'Lien non généré');
    }
    return data.properties.action_link;
  }

  /**
   * Génère un lien de réinitialisation de mot de passe pour un utilisateur
   * *déjà existant* (contrairement à generateInviteLink, ne crée aucun
   * compte) — même principe : ne passe jamais par le mailer de Supabase,
   * renvoie le lien pour que l'appelant le transmette lui-même. Pose
   * `needs_password_setup: true` sur le compte cible *avant* de générer le
   * lien (jamais dans les métadonnées du lien lui-même, dont le
   * comportement pour type: 'recovery' n'est pas garanti) pour que
   * SetPasswordPage s'affiche bien au clic, comme pour une invitation.
   */
  async generateRecoveryLink(userId: string): Promise<string> {
    const client = this.getClient();
    const { data: userData, error: userError } = await client.auth.admin.getUserById(userId);
    if (userError || !userData.user?.email) {
      throw new Error(userError?.message ?? 'Utilisateur introuvable');
    }
    const { error: updateError } = await client.auth.admin.updateUserById(userId, {
      user_metadata: { ...userData.user.user_metadata, needs_password_setup: true },
    });
    if (updateError) {
      throw new Error(updateError.message);
    }
    const { data, error } = await client.auth.admin.generateLink({
      type: 'recovery',
      email: userData.user.email,
      options: { redirectTo: APP_REDIRECT_URL },
    });
    if (error || !data.properties?.action_link) {
      throw new Error(error?.message ?? 'Lien non généré');
    }
    return data.properties.action_link;
  }
}
