import {test as ctBase, expect} from '@playwright/experimental-ct-react';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

const WEBAPP_ROOT = path.resolve(__dirname, '..');
const COVERAGE_DIR = path.join(WEBAPP_ROOT, '.v8-ct-coverage');

const COLLECT_COVERAGE = !process.env.CI;

function absolutizeSourceMap(mapJson: string): Record<string, unknown> {
    const map = JSON.parse(mapJson);
    if (Array.isArray(map.sources)) {
        map.sources = map.sources.map((source: string) =>
            'file://' + path.resolve(WEBAPP_ROOT, source.replace(/^(\.\.\/)+/, '')),
        );
    }
    delete map.sourceRoot;
    return map;
}

function lineLengths(source: string): number[] {
    return source.split('\n').map((line) => line.length);
}

export const test = ctBase.extend({
    page: async ({page}, use) => {
        if (COLLECT_COVERAGE) {
            await page.coverage.startJSCoverage({resetOnNavigation: false});
        }
        await use(page);
        if (!COLLECT_COVERAGE) {
            return;
        }
        const entries = await page.coverage.stopJSCoverage();

        const projectBundles = entries.filter(
            (e) => e.url.includes('/assets/') && !e.url.includes('jsx-runtime'),
        );

        if (projectBundles.length === 0) {
            return;
        }

        fs.mkdirSync(COVERAGE_DIR, {recursive: true});

        const sourceMapCache: Record<string, unknown> = {};
        const rewritten = [];

        for (const entry of projectBundles) {
            const basename = new URL(entry.url).pathname.split('/').pop()!;
            const fileUrl = 'file://' + path.join(COVERAGE_DIR, basename);

            try {
                const resp = await page.request.get(entry.url + '.map');
                if (resp.ok()) {
                    sourceMapCache[fileUrl] = {
                        lineLengths: lineLengths(entry.source ?? ''),
                        data: absolutizeSourceMap(await resp.text()),
                        url: fileUrl + '.map',
                    };
                }
            } catch {
                sourceMapCache[fileUrl] = undefined;
            }

            rewritten.push({
                scriptId: String(entry.scriptId),
                url: fileUrl,
                functions: entry.functions,
            });
        }

        fs.writeFileSync(
            path.join(COVERAGE_DIR, `coverage-${crypto.randomUUID()}.json`),
            JSON.stringify({
                result: rewritten,
                timestamp: Date.now(),
                'source-map-cache': sourceMapCache,
            }),
        );
    },
});

export {expect};
