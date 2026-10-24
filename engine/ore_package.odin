package engine

import "base:runtime"
import "core:bytes"
import "core:fmt"
import "core:encoding/endian"
import "core:hash"
import "core:log"
import "core:mem"
import os "osx"
import "core:path/filepath"
import "core:strings"
import zlib "vendor:zlib"

// ============================================================================
// ORE1 Portable Container Archive Format (.ore)
// ============================================================================
//
// Binary Layout:
// 1. Header (32 bytes):
//    - Magic:           4 bytes  ('O', 'R', 'E', '1')
//    - Version:         u32      (1)
//    - File Count:      u32      (number of entries in TOC)
//    - TOC Offset:      u64      (byte position where TOC begins)
//    - TOC Size:        u64      (byte length of TOC)
//    - Reserved/Flags:  u32      (0)
//
// 2. Data Payloads (contiguous):
//    - Raw or Zlib-compressed byte slices for each archived file.
//
// 3. Table of Contents (TOC) at TOC Offset:
//    - For each file:
//      - Path Length:        u16
//      - Path Bytes:         UTF-8 (normalized project-relative path)
//      - Data Offset:        u64 (absolute file offset in archive)
//      - Compressed Size:    u64
//      - Uncompressed Size:  u64
//      - Compression:        u8  (0 = Raw/Store, 1 = Zlib Deflate)
//      - CRC32:              u32
//
// ============================================================================

ORE_MAGIC :: [4]u8{'O', 'R', 'E', '1'}
ORE_VERSION :: 1

OreCompression :: enum u8 {
	Store = 0,
	Deflate = 1,
}

OreHeader :: struct #packed {
	magic:     [4]u8,
	version:   u32,
	fileCount: u32,
	tocOffset: u64,
	tocSize:   u64,
	flags:     u32,
}

OreEntry :: struct {
	path:             string,
	dataOffset:       u64,
	compressedSize:   u64,
	uncompressedSize: u64,
	compression:      OreCompression,
	crc32:            u32,
}

OrePackage :: struct {
	allocator: mem.Allocator,
	entries:   map[string]OreEntry,
	data:      []byte, // Full in-memory archive payload (if loaded into memory)
	filePath:  string, // Path on disk if streamed or loaded
	isMemory:  bool,
}

// ----------------------------------------------------------------------------
// Package Creation (Packing Directory to .ore)
// ----------------------------------------------------------------------------

OreFileSource :: struct {
	archivePath: string,
	diskPath:    string,
	data:        []byte,
	owned:       bool,
}

OrePackage_CreateFromFiles :: proc(sources: []OreFileSource, outPath: string, compress: bool = true) -> bool {
	context = Engine_DefaultContext()
	buf: bytes.Buffer
	bytes.buffer_init_allocator(&buf, 0, 1024, context.temp_allocator)
	defer bytes.buffer_destroy(&buf)

	// Write placeholder header (32 bytes)
	header := OreHeader{
		magic     = ORE_MAGIC,
		version   = ORE_VERSION,
		fileCount = u32(len(sources)),
		tocOffset = 0,
		tocSize   = 0,
		flags     = 0,
	}
	bytes.buffer_write(&buf, mem.byte_slice(&header, size_of(OreHeader)))

	entries := make([dynamic]OreEntry, context.temp_allocator)

	// Write payload data
	for src in sources {
		uncompressedData := src.data
		if len(uncompressedData) == 0 && src.diskPath != "" {
			diskData, err := os.read_entire_file(src.diskPath, context.temp_allocator)
			if err == nil {
				uncompressedData = diskData
			}
		}

		uncompressedLen := u64(len(uncompressedData))
		checksum := hash.crc32(uncompressedData)

		offset := u64(bytes.buffer_length(&buf))
		compType := OreCompression.Store
		compressedData: []byte = uncompressedData

		if compress && uncompressedLen > 64 {
			// Attempt zlib compression via vendor:zlib
			bound := zlib.compressBound(zlib.uLong(uncompressedLen))
			destBuf := make([]byte, int(bound), context.temp_allocator)
			destLen := zlib.uLongf(bound)
			res := zlib.compress(raw_data(destBuf), &destLen, raw_data(uncompressedData), zlib.uLong(uncompressedLen))
			if res == zlib.OK && int(destLen) < len(uncompressedData) {
				compType = .Deflate
				compressedData = destBuf[:destLen]
			}
		}

		compLen := u64(len(compressedData))
		bytes.buffer_write(&buf, compressedData)

		append(&entries, OreEntry{
			path             = src.archivePath,
			dataOffset       = offset,
			compressedSize   = compLen,
			uncompressedSize = uncompressedLen,
			compression      = compType,
			crc32            = checksum,
		})
	}

	// Write Table of Contents
	tocStart := u64(bytes.buffer_length(&buf))
	for entry in entries {
		pathBytes := transmute([]u8)entry.path
		pathLen := u16(len(pathBytes))

		pathLenBytes: [2]u8
		endian.unchecked_put_u16le(pathLenBytes[:], pathLen)
		bytes.buffer_write(&buf, pathLenBytes[:])
		bytes.buffer_write(&buf, pathBytes)

		metaBytes: [8 + 8 + 8 + 1 + 4]u8
		endian.unchecked_put_u64le(metaBytes[0:8], entry.dataOffset)
		endian.unchecked_put_u64le(metaBytes[8:16], entry.compressedSize)
		endian.unchecked_put_u64le(metaBytes[16:24], entry.uncompressedSize)
		metaBytes[24] = u8(entry.compression)
		endian.unchecked_put_u32le(metaBytes[25:29], entry.crc32)
		bytes.buffer_write(&buf, metaBytes[:])
	}
	tocEnd := u64(bytes.buffer_length(&buf))
	tocSize := tocEnd - tocStart

	// Patch final header
	finalSlice := bytes.buffer_to_bytes(&buf)
	finalHeader := cast(^OreHeader)&finalSlice[0]
	finalHeader.tocOffset = tocStart
	finalHeader.tocSize = tocSize

	writeErr := os.write_entire_file(outPath, finalSlice)
	if writeErr != nil {
		log.errorf("[OrePackage] Failed to write .ore file to: %s", outPath)
		return false
	}

	log.infof("[OrePackage] Successfully built package '%s' (%d files, %d bytes)", outPath, len(sources), len(finalSlice))
	return true
}

// Scans a directory recursively and packs all files into a single .ore file
// filter: which project files go in (nil = all); overrides: archive paths
// whose content is replaced (or added), e.g. a preset's project.json.
OrePackage_CreateFromDirectory :: proc(dirPath: string, outPath: string, compress: bool = true, filter: proc(path: string, data: rawptr) -> bool = nil, filterData: rawptr = nil, overrides: map[string][]u8 = nil) -> bool {
	context = Engine_DefaultContext()
	sources := make([dynamic]OreFileSource, context.temp_allocator)

	absDir, absErr := filepath.abs(dirPath, context.temp_allocator)
	if absErr != nil do return false

	for fullpath in os.walk_files(absDir) {
		{
			relPath, err := filepath.rel(absDir, fullpath, context.temp_allocator)
			// Hidden files and folders (.ore/ tooling, .luarc.json, editor
			// settings, .DS_Store) aren't part of the game.
			hidden := false
			unixRel, _ := strings.replace_all(relPath, "\\", "/", context.temp_allocator)
			for part in strings.split(unixRel, "/", context.temp_allocator) do if strings.has_prefix(part, ".") do hidden = true
			if err == nil && !hidden {
				norm := strings.join(strings.split(relPath, "\\", context.temp_allocator), "/", context.temp_allocator)
				if filter != nil && !filter(norm, filterData) do continue
				if norm in overrides do continue
				append(&sources, OreFileSource{
					archivePath = strings.clone(norm, context.temp_allocator),
					diskPath    = strings.clone(fullpath, context.temp_allocator),
					data        = nil,
					owned       = false,
				})
			}
		}
	}

	for path, data in overrides {
		append(&sources, OreFileSource{archivePath = path, data = data, owned = false})
	}
	return OrePackage_CreateFromFiles(sources[:], outPath, compress)
}

// ----------------------------------------------------------------------------
// Package Loading & Extraction
// ----------------------------------------------------------------------------

OrePackage_OpenFromMemory :: proc(data: []byte, allocator := context.allocator) -> (^OrePackage, bool) {
	if len(data) < size_of(OreHeader) {
		log.error("[OrePackage] Buffer too small for ORE header")
		return nil, false
	}

	header := cast(^OreHeader)&data[0]
	if header.magic != ORE_MAGIC {
		log.error("[OrePackage] Invalid magic header (not an ORE file)")
		return nil, false
	}
	if header.version != ORE_VERSION {
		log.errorf("[OrePackage] Unsupported ORE version: %d", header.version)
		return nil, false
	}

	if header.tocOffset + header.tocSize > u64(len(data)) {
		log.error("[OrePackage] Corrupted TOC bounds in ORE archive")
		return nil, false
	}

	pkg := new(OrePackage, allocator)
	pkg.allocator = allocator
	pkg.isMemory = true
	pkg.data = data
	pkg.entries = make(map[string]OreEntry, int(header.fileCount), allocator)

	// Parse TOC
	tocSlice := data[header.tocOffset : header.tocOffset + header.tocSize]
	offset := 0
	for _ in 0..<header.fileCount {
		if offset + 2 > len(tocSlice) do break
		pathLen := int(endian.unchecked_get_u16le(tocSlice[offset:offset+2]))
		offset += 2

		if offset + pathLen + 29 > len(tocSlice) do break
		pathStr := strings.clone(string(tocSlice[offset:offset+pathLen]), allocator)
		offset += pathLen

		meta := tocSlice[offset : offset + 29]
		dataOffset := endian.unchecked_get_u64le(meta[0:8])
		compSize := endian.unchecked_get_u64le(meta[8:16])
		uncompSize := endian.unchecked_get_u64le(meta[16:24])
		compType := OreCompression(meta[24])
		crc := endian.unchecked_get_u32le(meta[25:29])
		offset += 29

		pkg.entries[pathStr] = OreEntry{
			path             = pathStr,
			dataOffset       = dataOffset,
			compressedSize   = compSize,
			uncompressedSize = uncompSize,
			compression      = compType,
			crc32            = crc,
		}
	}

	return pkg, true
}

OrePackage_Open :: proc(path: string, allocator := context.allocator) -> (^OrePackage, bool) {
	data, readErr := os.read_entire_file(path, allocator)
	if readErr != nil {
		log.errorf("[OrePackage] Failed to open .ore file at: %s", path)
		return nil, false
	}

	pkg, okPkg := OrePackage_OpenFromMemory(data, allocator)
	if !okPkg {
		delete(data, allocator)
		return nil, false
	}
	pkg.filePath = strings.clone(path, allocator)
	return pkg, true
}

OrePackage_Close :: proc(pkg: ^OrePackage) {
	if pkg == nil do return

	for path, _ in pkg.entries {
		delete(path, pkg.allocator)
	}
	delete(pkg.entries)

	if pkg.filePath != "" {
		delete(pkg.filePath, pkg.allocator)
	}

	if pkg.isMemory && len(pkg.data) > 0 {
		delete(pkg.data, pkg.allocator)
	}

	free(pkg, pkg.allocator)
}

// Reads and decompresses a file from the package
OrePackage_ReadFile :: proc(pkg: ^OrePackage, path: string, allocator := context.allocator) -> ([]byte, bool) {
	if pkg == nil do return nil, false

	// Normalize lookup path
	norm := strings.join(strings.split(path, "\\", context.temp_allocator), "/", context.temp_allocator)
	entry, exists := pkg.entries[norm]
	if !exists {
		// Try without leading "./" or "/"
		trimmed := strings.trim_left(norm, "./")
		entry, exists = pkg.entries[trimmed]
		if !exists do return nil, false
	}

	if entry.dataOffset + entry.compressedSize > u64(len(pkg.data)) {
		log.errorf("[OrePackage] Read offset out of bounds for '%s'", path)
		return nil, false
	}

	rawSlice := pkg.data[entry.dataOffset : entry.dataOffset + entry.compressedSize]

	switch entry.compression {
	case .Store:
		out := make([]byte, entry.uncompressedSize, allocator)
		copy(out, rawSlice)
		return out, true

	case .Deflate:
		outBuf := make([]byte, int(entry.uncompressedSize), allocator)
		destLen := zlib.uLongf(entry.uncompressedSize)
		res := zlib.uncompress(raw_data(outBuf), &destLen, raw_data(rawSlice), zlib.uLong(len(rawSlice)))
		if res != zlib.OK {
			delete(outBuf, allocator)
			log.errorf("[OrePackage] Zlib decompression failed for '%s': %d", path, res)
			return nil, false
		}
		return outBuf[:destLen], true
	}

	return nil, false
}

// Reads file as a string
OrePackage_ReadString :: proc(pkg: ^OrePackage, path: string, allocator := context.allocator) -> (string, bool) {
	bytes, ok := OrePackage_ReadFile(pkg, path, allocator)
	if !ok do return "", false
	return string(bytes), true
}

// Checks if a file path exists in the package
OrePackage_HasFile :: proc(pkg: ^OrePackage, path: string) -> bool {
	if pkg == nil do return false
	norm := strings.join(strings.split(path, "\\", context.temp_allocator), "/", context.temp_allocator)
	if _, exists := pkg.entries[norm]; exists do return true
	trimmed := strings.trim_left(norm, "./")
	_, exists := pkg.entries[trimmed]
	return exists
}
