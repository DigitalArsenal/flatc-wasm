# flatc-wasm

> An isomorphic WebAssembly wrapper for the [FlatBuffers](https://github.com/google/flatbuffers) `flatc` compiler — usable in **Node.js**, **Deno**, and the **Browser**. Maintained at [DigitalArsenal/flatc-wasm](https://github.com/DigitalArsenal/flatc-wasm).

This package provides a unified interface to run `flatc` entirely in JavaScript environments. It wraps the Emscripten-compiled WASM binary of `flatc` and exposes ergonomic methods for:

- Schema compilation (`.fbs`)
- JSON ⇄ Binary `.mon` roundtrip
- Code generation (TS, C++, etc.)
- Support for browsers, Deno, and Node.js

---

## Installation

### Node.js

```bash
npm install flatc-wasm
```

### Deno

```ts
import { FlatcRunner } from "npm:flatc-wasm"
```

> Also works from `unpkg` or any CDN when bundled via Vite, Rollup, or Webpack.

---

## Repository

- GitHub: [DigitalArsenal/flatc-wasm](https://github.com/DigitalArsenal/flatc-wasm)

---

## Example Usage

```js
import { FlatcRunner } from "flatc-wasm";

const schemaInput = {
  entry: "/monster_test.fbs",
  files: {
    "/monster_test.fbs": await fetch("/schemas/monster_test.fbs").then((r) =>
      r.text()
    ),
  },
};

const runner = await FlatcRunner.init();

// Compile JSON payload -> FlatBuffer binary
const binary = runner.generateBinary(
  schemaInput,
  JSON.stringify({ hp: 100, mana: 50, name: "Orc" })
);

// Read the binary back into JSON text
const jsonText = runner.generateJSON(schemaInput, {
  path: "/monster.mon",
  data: binary,
});
```

---

## API Reference

### Exports

- `FlatcRunner` — imperative interface to the `flatc` CLI compiled to WebAssembly.
- `StreamingTransformer` — stateless helper that spins up fresh runners for per-request transforms.

Both exports ship as ES modules that run in Node.js ≥ 18, modern browsers (when bundled), and Deno.

---

### FlatcRunner

```ts
/**
 * Create and initialize a FlatcRunner.
 *
 * @param {Object} [options]
 * @param {Writable} [options.stdoutStream=null] - Receives stdout as chunks are emitted.
 * @param {Writable} [options.stderrStream=null] - Receives stderr as chunks are emitted.
 * @param {Function} [options.print] - Advanced hook to override the Emscripten print function.
 * @param {Function} [options.printErr] - Advanced hook to override the Emscripten error printer.
 * @returns {Promise<FlatcRunner>}
 */
FlatcRunner.init(options?);
```

Virtual filesystem helpers:

```ts
/**
 * Mount a single file inside the wasm virtual filesystem.
 * @param {string} path
 * @param {string|Uint8Array} data
 * @returns {void}
 */
runner.mountFile(path, data);

/**
 * Mount multiple files in a single call.
 * @param {{ path: string, data: string|Uint8Array }[]} files
 * @returns {void}
 */
runner.mountFiles(files);

/**
 * Recursively list every file beneath the given directory.
 * @param {string} path
 * @returns {string[]}
 */
runner.listAllFiles(path);
```

Mounted files persist between calls. Generator helpers cache the most recent schema tree and reuse it automatically when the contents match.

Schema input typedefs:

```ts
/**
 * @typedef {Object} SchemaInput
 * @property {string} entry - Absolute path to the entry .fbs file inside the wasm filesystem.
 * @property {Record<string, string|Uint8Array>} files - Map of virtual paths to file contents.
 */

/**
 * @typedef {Object} BinaryInput
 * @property {string} path - Destination path inside the wasm filesystem.
 * @property {Uint8Array} data - Raw FlatBuffer bytes.
 */
```

Generator helpers:

```ts
/**
 * Serialize JSON into a FlatBuffer binary.
 * @param {SchemaInput} schemaInput
 * @param {string|Uint8Array} jsonInput
 * @returns {Uint8Array}
 */
runner.generateBinary(schemaInput, jsonInput);

/**
 * @typedef {Object} GenerateJsonOptions
 * @property {boolean} [rawBinary=true] - Set false if the binary has already been mounted.
 * @property {boolean} [defaultsJson=false] - Include default values in the output JSON.
 * @property {"utf8"|null} [encoding=null] - Return a UTF-8 string when set to "utf8".
 */

/**
 * Deserialize a FlatBuffer binary into JSON.
 * @param {SchemaInput} schemaInput
 * @param {BinaryInput} binaryInput
 * @param {GenerateJsonOptions} [options]
 * @returns {string|Uint8Array}
 */
runner.generateJSON(schemaInput, binaryInput, options?);

/**
 * @typedef {"cpp"|"csharp"|"dart"|"go"|"java"|"json"|"jsonschema"|"kotlin"|"kotlin-kmp"|"lobster"|"lua"|"nim"|"php"|"python"|"rust"|"swift"|"ts"} SupportedLanguage
 *
 * @typedef {Object} GenerateCodeOptions
 * @property {boolean} [genObjectApi]
 * @property {boolean} [genOneFile]
 * @property {boolean} [pythonTyping]
 * @property {boolean} [pythonVersion]
 * @property {boolean} [noIncludes]
 * @property {boolean} [genCompare]
 * @property {boolean} [genNameStrings]
 * @property {boolean} [reflectNames]
 * @property {boolean} [reflectTypes]
 * @property {boolean} [genJsonEmit]
 * @property {boolean} [keepPrefix]
 * @property {boolean} [preserveCase]
 */

/**
 * Generate source files for a target language.
 * @param {SchemaInput} schemaInput
 * @param {SupportedLanguage} language
 * @param {string} [outputDir] - Optional virtual output directory.
 * @param {GenerateCodeOptions} [options]
 * @returns {Record<string, string>} - Map of relative output paths to UTF-8 source.
 */
runner.generateCode(schemaInput, language, outputDir?, options?);
```

Direct `flatc` access:

```ts
/**
 * Execute the underlying flatc binary with raw CLI arguments.
 * @param {string[]} args
 * @returns {{ code: number, stdout: string, stderr: string }}
 */
runner.runCommand(args);

/**
 * @returns {string} flatc usage text.
 */
runner.help();

/**
 * @returns {string} flatc version string.
 */
runner.version();

/**
 * Retrieve errors recorded by internal helpers.
 * @returns {Error[]}
 */
runner.getErrors();
```

Need to wipe the virtual filesystem? Inspect with `runner.listAllFiles("/")` and remove entries via `runner.Module.FS.unlink(path)`.

---

### StreamingTransformer

Use the transformer when you need short-lived, isolated conversions (for example, per HTTP request). Each call spins up a fresh runner, preventing shared state between transforms.

```ts
/**
 * Create a StreamingTransformer bound to a schema tree.
 * @param {SchemaInput} schemaInput
 * @returns {Promise<StreamingTransformer>}
 */
StreamingTransformer.create(schemaInput);

/**
 * Convert JSON into FlatBuffer binary using an isolated runner.
 * @param {string|Uint8Array} json
 * @returns {Promise<Uint8Array>}
 */
transformer.transformJsonToBinary(json);

/**
 * Convert FlatBuffer binary back into JSON (returned as bytes).
 * @param {Uint8Array} buffer
 * @returns {Promise<Uint8Array>}
 */
transformer.transformBinaryToJson(buffer);
```

Internally each call allocates a new `FlatcRunner`, performs the transform, and then tears down the wasm filesystem to avoid leaking state or memory across requests.

---

## Testing

### Node

```bash
npm test
```

### Deno

```bash
deno task test
```

> Make sure you provide permissions like `--allow-read` and `--allow-env`.

---

## 📖 License

[Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
