import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { createClient } from '@supabase/supabase-js';

export const PRODUCT_IMAGES_BUCKET = 'product-images';
const SIGNED_URL_TTL_SECONDS = 60 * 60; // 1h — the Flutter client refreshes as needed rather than caching long-lived URLs.

/**
 * Talks to Supabase Storage as the *authenticated user* (their own bearer
 * token, not a service_role key) so storage.objects RLS enforces tenant
 * isolation the same way it does for a direct client call — NestJS still
 * decides *what* gets uploaded (validation, resizing), but never needs a
 * service_role secret for this.
 */
@Injectable()
export class SupabaseStorageService {
  private clientFor(accessToken: string) {
    const supabaseUrl = process.env.SUPABASE_URL;
    const anonKey = process.env.SUPABASE_ANON_KEY;
    if (!supabaseUrl || !anonKey) {
      throw new InternalServerErrorException('SUPABASE_URL / SUPABASE_ANON_KEY ne sont pas configurés');
    }
    return createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  async upload(accessToken: string, path: string, body: Buffer, contentType: string): Promise<void> {
    const { error } = await this.clientFor(accessToken)
      .storage.from(PRODUCT_IMAGES_BUCKET)
      .upload(path, body, { contentType, upsert: true });
    if (error) {
      throw new InternalServerErrorException(`Échec de l'upload de l'image : ${error.message}`);
    }
  }

  async remove(accessToken: string, paths: string[]): Promise<void> {
    if (paths.length === 0) return;
    const { error } = await this.clientFor(accessToken).storage.from(PRODUCT_IMAGES_BUCKET).remove(paths);
    if (error) {
      throw new InternalServerErrorException(`Échec de la suppression de l'image : ${error.message}`);
    }
  }

  async createSignedUrl(accessToken: string, path: string): Promise<string> {
    const { data, error } = await this.clientFor(accessToken)
      .storage.from(PRODUCT_IMAGES_BUCKET)
      .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);
    if (error || !data) {
      throw new InternalServerErrorException(`Échec de la génération de l'URL signée : ${error?.message}`);
    }
    return data.signedUrl;
  }
}
