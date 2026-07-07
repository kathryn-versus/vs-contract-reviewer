// mammoth's browser build doesn't ship its own TypeScript types under this
// subpath — same situation as pdf-parse. Declaring it as untyped (implicit
// any) is enough to satisfy the stricter production build's type check.
declare module 'mammoth/mammoth.browser';
