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
   *
   * Reste vulnérable au problème documenté sur generateInviteLink/generateRecoveryLink
   * ci-dessous (un lien à usage unique consommé par un robot d'aperçu avant
   * le vrai clic) côté client e-mail du destinataire (Outlook Safe Links et
   * certains antivirus font la même chose) — aucun correctif possible ici
   * sans changer le modèle d'e-mail Supabase, hors d'accès (pas de tableau
   * de bord).
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
   * quota gratuit partagé est atteint (voir docs/api/users.md).
   *
   * Renvoie un lien vers l'application elle-même (`?token_hash=&type=`),
   * **pas** `action_link` (le `/auth/v1/verify?token=...` fourni par
   * Supabase) : ce dernier est à usage unique et la vérification s'y
   * déclenche sur un simple GET — or WhatsApp (confirmé en conditions
   * réelles le 2026-09-09 via les journaux Supabase) et d'autres apps de
   * messagerie visitent automatiquement tout lien partagé pour en générer
   * un aperçu, ce qui consomme le jeton avant même que la personne ne
   * clique elle-même. `LinkConfirmationGate` côté Flutter appelle
   * `verifyOTP(tokenHash: ...)` lui-même, uniquement quand du code Dart
   * s'exécute réellement dans un navigateur — un robot d'aperçu qui ne
   * charge jamais JavaScript ne consomme donc plus le jeton.
   */
  async generateInviteLink(email: string, metadata: Record<string, string | boolean>): Promise<string> {
    const { data, error } = await this.getClient().auth.admin.generateLink({
      type: 'invite',
      email,
      options: { data: metadata, redirectTo: APP_REDIRECT_URL },
    });
    if (error || !data.properties?.hashed_token) {
      throw new Error(error?.message ?? 'Lien non généré');
    }
    return `${APP_REDIRECT_URL}/?token_hash=${data.properties.hashed_token}&type=invite`;
  }

  /**
   * Génère un lien de réinitialisation de mot de passe pour un utilisateur
   * *déjà existant* (contrairement à generateInviteLink, ne crée aucun
   * compte) — même principe : ne passe jamais par le mailer de Supabase,
   * renvoie un lien vers l'application (`?token_hash=&type=recovery`,
   * jamais `action_link` — voir generateInviteLink pour pourquoi). Pose
   * `needs_password_setup: true` sur le compte cible *avant* de générer le
   * lien pour que `SetPasswordPage` s'affiche bien une fois vérifié.
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
    if (error || !data.properties?.hashed_token) {
      throw new Error(error?.message ?? 'Lien non généré');
    }
    return `${APP_REDIRECT_URL}/?token_hash=${data.properties.hashed_token}&type=recovery`;
  }
}
