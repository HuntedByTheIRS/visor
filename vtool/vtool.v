// vtool runs the V compiler and turns what it prints into values the rest of
// visor can use.
//
// The compiler is reached as a subprocess, never as a library. V's package
// internals move between releases, and a language server that links them is
// rebuilt or broken on the compiler's schedule instead of its own. Staying at
// the process boundary keeps visor's coupling down to what V documents: the
// shape of a `-check` diagnostic, and the output of `v fmt -` and `v version`.
//
// Two rules hold throughout. An editor buffer reaches the compiler on stdin, so
// nothing lands on disk and an unsaved buffer can still be diagnosed. A
// capability that is absent is reported as absent, because an empty successful
// result is indistinguishable from a clean file, and that confusion is the one
// this module exists to prevent.
module vtool
