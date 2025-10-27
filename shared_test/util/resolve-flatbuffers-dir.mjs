import process from "node:process";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function resolveFlatbuffersDir() {
  if (process.env.FLATBUFFERS_DIR) {
    return process.env.FLATBUFFERS_DIR;
  }

  const repoRoot = path.resolve(__dirname, "..", "..");
  const candidates = [
    path.join(repoRoot, "flatbuffers"),
    path.join(repoRoot, "packages", "flatbuffers"),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  throw new Error(
    "FlatBuffers directory not found. Set FLATBUFFERS_DIR or run ./build.sh.",
  );
}
