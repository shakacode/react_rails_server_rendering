import path from 'path';
import fs from 'fs';

const loadedReactClientManifests = new Map<string, { [key: string]: unknown; }>();

export default function loadReactClientManifest(reactClientManifestFileName: string) {
  // React client manifest is uploaded to node renderer as an asset.
  // Renderer copies assets to the same place as the server-bundle.js and rsc-bundle.js.
  // Thus, the __dirname of this code is where we can find the manifest file.
  const manifestPath = path.resolve(__dirname, reactClientManifestFileName);
  if (!loadedReactClientManifests.has(manifestPath)) {
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    loadedReactClientManifests.set(manifestPath, manifest);
  }

  return loadedReactClientManifests.get(manifestPath)!;
}
