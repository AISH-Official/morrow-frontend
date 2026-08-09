import {copyFile, mkdir, writeFile} from 'node:fs/promises';

const dist = new URL('../dist/', import.meta.url);
const index = new URL('index.html', dist);
const devicePreview = new URL('device-preview/', dist);

await mkdir(devicePreview, {recursive: true});
await copyFile(index, new URL('index.html', devicePreview));
await copyFile(index, new URL('404.html', dist));
await writeFile(new URL('.nojekyll', dist), '');
