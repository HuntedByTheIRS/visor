## What changed

<!-- One or two sentences. What is different now, and why. -->

## Verification

- [ ] `v -o /tmp/visor .` exits 0
- [ ] `v fmt -verify .` exits 0
- [ ] `v test .` is green
- [ ] `npx --yes markdownlint-cli2@0.23.3` is green
- [ ] the compiler-internal import and V1 protocol grep gates pass
- [ ] every command reported here was run from a clean checkout

## Prose audit

- [ ] the humanizer pass ran over every line of prose this change adds:
      commit message, docs, comments and any error text a person reads
- [ ] no significance inflation, no `-ing` analysis tails, no rule-of-three
      lists, no em dashes, no bolded inline headers, no upbeat closing

## Rules

- [ ] no `v.ast`, `v.flat`, `v.parser`, `v.checker`, `v.pref` or `v.scanner` import
- [ ] no `-vls-mode` and no `-line-info`
- [ ] no vls source copied, pasted or adapted
- [ ] no source file over roughly 4 kLOC
- [ ] the commits are small and each one is a single logical change
