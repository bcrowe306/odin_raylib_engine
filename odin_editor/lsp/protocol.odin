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
}

// --- completion ---

CompletionParams :: struct {
	textDocument: TextDocumentIdentifier `json:"textDocument"`,
	position:     Position               `json:"position"`,
}

CompletionItem :: struct {
	label:  string `json:"label"`,
	kind:   int    `json:"kind"`,
	detail: string `json:"detail"`,
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
}

// --- diagnostics ---

Diagnostic :: struct {
	range:    Range  `json:"range"`,
	severity: int    `json:"severity"`,
	message:  string `json:"message"`,
}

// --- hover ---

HoverParams :: struct {
	textDocument: TextDocumentIdentifier `json:"textDocument"`,
	position:     Position               `json:"position"`,
}
