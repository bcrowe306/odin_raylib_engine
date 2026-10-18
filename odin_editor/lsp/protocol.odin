// LSP protocol data structures (the subset this editor needs). Field names
// use `json` tags to match the protocol's camelCase wire format.
package lsp

Position :: struct {
	line:      int `json:"line"`,
	character: int `json:"character"`,
}

Range :: struct {
	start: Position `json:"start"`,
	end:   Position `json:"end"`,
}

TextDocumentIdentifier :: struct {
	uri: string `json:"uri"`,
}

VersionedTextDocumentIdentifier :: struct {
	uri:     string `json:"uri"`,
	version: int    `json:"version"`,
}

TextDocumentItem :: struct {
	uri:         string `json:"uri"`,
	languageId:  string `json:"languageId"`,
	version:     int    `json:"version"`,
	text:        string `json:"text"`,
}

TextDocumentPositionParams :: struct {
	textDocument: TextDocumentIdentifier `json:"textDocument"`,
	position:     Position               `json:"position"`,
}

// --- initialize ---

InitializeParams :: struct {
	processId:             Maybe(int)   `json:"processId"`,
	rootUri:               Maybe(string) `json:"rootUri"`,
	capabilities:          ClientCapabilities `json:"capabilities"`,
}

ClientCapabilities :: struct {}

// --- textDocument/didOpen, didChange, didClose, didSave ---

DidOpenTextDocumentParams :: struct {
	textDocument: TextDocumentItem `json:"textDocument"`,
}

TextDocumentContentChangeEvent :: struct {
	text: string `json:"text"`,
}

DidChangeTextDocumentParams :: struct {
	textDocument:   VersionedTextDocumentIdentifier    `json:"textDocument"`,
	contentChanges: []TextDocumentContentChangeEvent    `json:"contentChanges"`,
}

DidCloseTextDocumentParams :: struct {
	textDocument: TextDocumentIdentifier `json:"textDocument"`,
}

DidSaveTextDocumentParams :: struct {
	textDocument: TextDocumentIdentifier `json:"textDocument"`,
	// Servers that register `save: {includeText: true}` (OLS does) re-index
	// the file from this; omitting it makes OLS index an empty file.
	text:         string                 `json:"text"`,
}

// --- completion ---

CompletionParams :: struct {
	textDocument: TextDocumentIdentifier `json:"textDocument"`,
	position:     Position               `json:"position"`,
}

CompletionItem :: struct {
	label:       string `json:"label"`,
	kind:        int    `json:"kind"`,
	detail:      string `json:"detail"`,
	// Text to insert on accept (falls back to `label` when empty).
	insert_text: string `json:"insertText"`,
	// Text to match the typed prefix against (falls back to `label`).
	filter_text: string `json:"filterText"`,
	// If the server supplied a `textEdit`, its replacement range; the
	// editor replaces [text_edit_range.start, cursor) with insert_text.
	has_text_edit:   bool  `json:"-"`,
	text_edit_range: Range `json:"-"`,
}

// CompletionItemKind values from the LSP spec (the subset worth labeling).
CompletionKind :: enum int {
	Text = 1, Method = 2, Function = 3, Constructor = 4, Field = 5,
	Variable = 6, Class = 7, Interface = 8, Module = 9, Property = 10,
	Unit = 11, Value = 12, Enum = 13, Keyword = 14, Snippet = 15,
	Color = 16, File = 17, Reference = 18, Folder = 19, EnumMember = 20,
	Constant = 21, Struct = 22, Event = 23, Operator = 24, TypeParameter = 25,
}

// --- signatureHelp ---

SignatureHelpParams :: struct {
	textDocument: TextDocumentIdentifier `json:"textDocument"`,
	position:     Position               `json:"position"`,
}

ParameterInformation :: struct {
	label: string `json:"label"`,
}

SignatureInformation :: struct {
	label:      string                  `json:"label"`,
	parameters: []ParameterInformation  `json:"parameters"`,
	// Per-signature active parameter (LSP 3.16+); -1 when the server
	// didn't send one, in which case the response-level value applies.
	active_parameter: int `json:"-"`,
}

// --- diagnostics ---

Diagnostic :: struct {
	range:    Range  `json:"range"`,
	// 1 error, 2 warning, 3 information, 4 hint (0/absent -> error).
	severity: int    `json:"severity"`,
	message:  string `json:"message"`,
	source:   string `json:"source"`,
}

// --- hover ---

HoverParams :: struct {
	textDocument: TextDocumentIdentifier `json:"textDocument"`,
	position:     Position               `json:"position"`,
}
