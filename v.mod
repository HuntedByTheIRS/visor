// Feature modules live in real subdirectories (vtool/, engine/, lsp/, diag/,
// features/) and are imported by name.
//
// `subdirs` is deliberately absent. In V 0.5.2 it declares one virtual module
// spread across the directories it lists, which is the layout that broke
// v-analyzer's build. Real subdirectory modules need no manifest entry.
Module {
	name: 'visor'
	description: 'A language server for V.'
	version: '0.0.2'
	license: 'MIT'
	dependencies: []
}
