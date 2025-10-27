import { describe, it, expect } from "vitest";
import { FlatcRunner } from "../src/index.mjs";
import path from "node:path";
import fs from "node:fs/promises";
import { Writable } from "node:stream";
import { runFlatcRoundTripTest } from "../shared_test/json-binary-test.mjs";
import { loadFbsFiles } from "../shared_test/util/load-fbs-files.mjs";
import { resolveFlatbuffersDir } from "../shared_test/util/resolve-flatbuffers-dir.mjs";

const FLATBUFFERS_DIR = resolveFlatbuffersDir();
const TEST_ROOT = path.join(FLATBUFFERS_DIR, "tests");
const JSON_FILE = path.join(TEST_ROOT, "monsterdata_test.json");
const MON_FILE = path.join(TEST_ROOT, "monsterdata_test.mon");

describe("FlatcRunner", () => {
  it("should round-trip flatbuffer JSON to binary and back to JSON", async () => {
    const stdoutStream = new Writable({
      write(chunk, _, cb) {
        cb();
      },
    });

    const { actual, expected } = await runFlatcRoundTripTest({
      FlatcRunner,
      loadFbsFiles: () => loadFbsFiles(TEST_ROOT),
      readJsonFile: () => fs.readFile(JSON_FILE, "utf8"),
      readMonFile: () => fs.readFile(MON_FILE),
      createStdoutStream: () => stdoutStream,
    });

    expect(actual).toEqual(expected);
  });
});
