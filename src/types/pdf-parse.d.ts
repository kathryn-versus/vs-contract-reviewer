// pdf-parse doesn't ship its own TypeScript types, and there's no matching
// @types/pdf-parse package to install — this just tells TypeScript to treat
// it as untyped (implicit any) instead of failing the production build,
// which type-checks more strictly than local `next dev` does.
declare module 'pdf-parse';
