// Shared between client and server code, so it must not import 'server-only'.
export const ALLOWED_DOMAIN_SERVER = process.env.NEXT_PUBLIC_ALLOWED_DOMAIN ?? 'vsnyc.tv';
